// LuminaVaultClient/LuminaVaultClient/Features/Kanban/KanbanBoardViewModel.swift
//
// Board view model: loads a board, polls for remote version changes,
// and applies optimistic local mutations for all CRUD operations.
//
// Swift 6 isolation note: `board` is @MainActor-isolated. The poll Task
// captures `self` as `@MainActor` because the enclosing class is
// @MainActor — `await self.board` inside a plain `Task { }` spawned
// from a @MainActor context is correct; the compiler allows it because
// the Task inherits the actor context of the enclosing scope.

import Foundation
import LuminaVaultShared

@Observable
@MainActor
final class KanbanBoardViewModel {
    private(set) var board: BoardDTO?
    var lastError: String?
    var isLoading = false

    private let boardID: UUID
    private let client: any KanbanClientProtocol
    private var pollTask: Task<Void, Never>?

    init(boardID: UUID, client: any KanbanClientProtocol) {
        self.boardID = boardID
        self.client = client
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            board = try await client.board(boardID)
        } catch {
            lastError = errorText(error)
        }
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { continue }
                // Both `board` and `boardID` are @MainActor-isolated.
                // This Task was spawned from a @MainActor context so
                // the compiler knows the closure runs on MainActor.
                let current = self.board
                guard let current else { continue }
                if let v = try? await self.client.version(self.boardID),
                   v.version != current.version
                {
                    await self.load()
                }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func addColumn(title: String) async {
        do {
            board = try await client.createColumn(boardID: boardID, title: title)
        } catch {
            lastError = errorText(error)
            await load()
        }
    }

    func renameColumn(_ id: UUID, title: String) async {
        do {
            board = try await client.patchColumn(boardID: boardID, columnID: id, title: title)
        } catch {
            lastError = errorText(error)
            await load()
        }
    }

    func deleteColumn(_ id: UUID) async {
        do {
            board = try await client.deleteColumn(boardID: boardID, columnID: id)
        } catch {
            lastError = errorText(error)
            await load()
        }
    }

    func addCard(columnID: UUID, title: String) async {
        do {
            let card = try await client.createCard(boardID: boardID, .init(columnID: columnID, title: title))
            apply { insert(card, into: columnID, &$0) }
        } catch {
            lastError = errorText(error)
            await load()
        }
    }

    func editCard(_ id: UUID, _ req: CardPatchRequest) async {
        do {
            let updated = try await client.patchCard(cardID: id, req)
            apply { replace(updated, in: &$0) }
        } catch {
            lastError = errorText(error)
            await load()
        }
    }

    func deleteCard(_ id: UUID) async {
        apply { remove(id, from: &$0) }
        do {
            try await client.deleteCard(cardID: id)
        } catch {
            lastError = errorText(error)
            await load()
        }
    }

    func moveCard(_ id: UUID, toColumn: UUID, before: UUID?, after: UUID?) async {
        apply { optimisticMove(id, toColumn: toColumn, &$0) }
        do {
            let updated = try await client.moveCard(
                cardID: id,
                .init(toColumnID: toColumn, beforeID: before, afterID: after)
            )
            apply { replace(updated, in: &$0) }
        } catch {
            lastError = errorText(error)
            await load()
        }
    }

    /// Promote a card to a scheduled Job. Reloads the board on success so the
    /// card's `jobConfig` (now carrying the job slug) is reflected. Returns the
    /// created job, or nil on failure (with `lastError` set).
    @discardableResult
    func promoteCard(_ id: UUID, _ req: CardPromoteRequest) async -> SkillDTO? {
        do {
            let job = try await client.promoteCard(cardID: id, req)
            await load()
            return job
        } catch {
            lastError = errorText(error)
            return nil
        }
    }

    // MARK: - Local mutation helpers

    private func apply(_ mutate: (inout BoardDTO) -> Void) {
        guard var b = board else { return }
        mutate(&b)
        board = b
    }

    private func insert(_ card: CardDTO, into columnID: UUID, _ b: inout BoardDTO) {
        b = withColumns(b) { cols in
            cols.map { col in
                col.id == columnID
                    ? ColumnDTO(
                        id: col.id,
                        title: col.title,
                        rank: col.rank,
                        cards: (col.cards + [card]).sorted { $0.rank < $1.rank }
                    )
                    : col
            }
        }
    }

    private func remove(_ cardID: UUID, from b: inout BoardDTO) {
        b = withColumns(b) { cols in
            cols.map { col in
                ColumnDTO(
                    id: col.id,
                    title: col.title,
                    rank: col.rank,
                    cards: col.cards.filter { $0.id != cardID }
                )
            }
        }
    }

    private func replace(_ card: CardDTO, in b: inout BoardDTO) {
        remove(card.id, from: &b)
        insert(card, into: card.columnID, &b)
    }

    private func optimisticMove(_ id: UUID, toColumn: UUID, _ b: inout BoardDTO) {
        guard let existing = b.columns.flatMap(\.cards).first(where: { $0.id == id }) else { return }
        remove(id, from: &b)
        let moved = CardDTO(
            id: existing.id,
            columnID: toColumn,
            title: existing.title,
            body: existing.body,
            priority: existing.priority,
            dueAt: existing.dueAt,
            rank: existing.rank,
            updatedAt: existing.updatedAt
        )
        insert(moved, into: toColumn, &b)
    }

    private func withColumns(_ b: BoardDTO, _ f: ([ColumnDTO]) -> [ColumnDTO]) -> BoardDTO {
        BoardDTO(id: b.id, title: b.title, version: b.version, columns: f(b.columns))
    }

    private func errorText(_ e: any Error) -> String {
        (e as? APIError)?.errorDescription ?? e.localizedDescription
    }
}
