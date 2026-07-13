// LuminaVaultClient/LuminaVaultClient/API/Kanban/KanbanHTTPClient.swift
//
// Concrete KanbanClientProtocol backed by BaseHTTPClient.

import Foundation
import LuminaVaultShared

final class KanbanHTTPClient: KanbanClientProtocol {
    private let client: BaseHTTPClient
    private let versions = KanbanVersionStore()

    init(client: BaseHTTPClient) {
        self.client = client
    }

    func listBoards() async throws -> [BoardSummaryDTO] {
        let boards = try await client.execute(KanbanEndpoints.ListBoards())
        for board in boards {
            await versions.record(boardID: board.id, version: board.version)
        }
        return boards
    }

    func board(_ id: UUID) async throws -> BoardDTO {
        let board = try await client.execute(KanbanEndpoints.GetBoard(id: id))
        await versions.record(board)
        return board
    }

    func version(_ id: UUID) async throws -> BoardVersionDTO {
        let version = try await client.execute(KanbanEndpoints.GetVersion(id: id))
        await versions.record(boardID: id, version: version.version)
        return version
    }

    func createColumn(boardID: UUID, title: String) async throws -> BoardDTO {
        let result = try await client.execute(KanbanEndpoints.CreateColumn(
            boardID: boardID, title: title, expectedVersion: await versions.version(boardID: boardID)
        ))
        await versions.record(result)
        return result
    }

    func patchColumn(boardID: UUID, columnID: UUID, title: String) async throws -> BoardDTO {
        let result = try await client.execute(KanbanEndpoints.PatchColumn(
            boardID: boardID, columnID: columnID, title: title,
            expectedVersion: await versions.version(boardID: boardID)
        ))
        await versions.record(result)
        return result
    }

    func deleteColumn(boardID: UUID, columnID: UUID) async throws -> BoardDTO {
        let result = try await client.execute(KanbanEndpoints.DeleteColumn(
            boardID: boardID, columnID: columnID,
            expectedVersion: await versions.version(boardID: boardID)
        ))
        await versions.record(result)
        return result
    }

    func createCard(boardID: UUID, _ req: CardCreateRequest) async throws -> CardDTO {
        let card = try await client.execute(KanbanEndpoints.CreateCard(
            boardID: boardID, request: req, expectedVersion: await versions.version(boardID: boardID)
        ))
        _ = try? await version(boardID)
        return card
    }

    func patchCard(cardID: UUID, _ req: CardPatchRequest) async throws -> CardDTO {
        let boardID = await versions.boardID(cardID: cardID)
        var expected: Int64?
        if let boardID {
            expected = await versions.version(boardID: boardID)
        }
        let card = try await client.execute(KanbanEndpoints.PatchCard(
            cardID: cardID, request: req,
            expectedVersion: expected
        ))
        if let boardID {
            _ = try? await version(boardID)
        }
        return card
    }

    func deleteCard(cardID: UUID) async throws {
        let boardID = await versions.boardID(cardID: cardID)
        var expected: Int64?
        if let boardID {
            expected = await versions.version(boardID: boardID)
        }
        _ = try await client.execute(KanbanEndpoints.DeleteCard(
            cardID: cardID,
            expectedVersion: expected
        ))
        if let boardID {
            _ = try? await version(boardID)
        }
    }

    func moveCard(cardID: UUID, _ req: CardMoveRequest) async throws -> CardDTO {
        let boardID = await versions.boardID(cardID: cardID)
        var expected: Int64?
        if let boardID {
            expected = await versions.version(boardID: boardID)
        }
        let card = try await client.execute(KanbanEndpoints.MoveCard(
            cardID: cardID, request: req,
            expectedVersion: expected
        ))
        if let boardID {
            _ = try? await version(boardID)
        }
        return card
    }

    func promoteCard(cardID: UUID, _ req: CardPromoteRequest) async throws -> SkillDTO {
        let boardID = await versions.boardID(cardID: cardID)
        var expected: Int64?
        if let boardID {
            expected = await versions.version(boardID: boardID)
        }
        let result = try await client.execute(KanbanEndpoints.PromoteCard(
            cardID: cardID, request: req,
            expectedVersion: expected
        ))
        if let boardID {
            _ = try? await version(boardID)
        }
        return result
    }
}
