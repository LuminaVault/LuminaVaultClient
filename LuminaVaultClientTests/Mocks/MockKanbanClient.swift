// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockKanbanClient.swift
//
// Scripted KanbanClientProtocol fake. Each call route can be pre-loaded
// with either a success value or an Error; tests assert on the recorded
// call list after exercising the ViewModel.

@testable import LuminaVaultClient
import Foundation
import LuminaVaultShared

final class MockKanbanClient: KanbanClientProtocol, @unchecked Sendable {

    // MARK: - Configurable results

    var listBoardsResult: Result<[BoardSummaryDTO], Error> = .success([])
    var boardResult: Result<BoardDTO, Error> = .success(.stub())
    var versionResult: Result<BoardVersionDTO, Error> = .success(BoardVersionDTO(version: 1))
    var createColumnResult: Result<BoardDTO, Error> = .success(.stub())
    var patchColumnResult: Result<BoardDTO, Error> = .success(.stub())
    var deleteColumnResult: Result<BoardDTO, Error> = .success(.stub())
    var createCardResult: Result<CardDTO, Error> = .success(.stub())
    var patchCardResult: Result<CardDTO, Error> = .success(.stub())
    var deleteCardError: Error?
    var moveCardResult: Result<CardDTO, Error> = .success(.stub())

    // MARK: - Call recording

    private(set) var calls: [Call] = []

    enum Call: Equatable {
        case listBoards
        case board(UUID)
        case version(UUID)
        case createColumn(boardID: UUID, title: String)
        case patchColumn(boardID: UUID, columnID: UUID, title: String)
        case deleteColumn(boardID: UUID, columnID: UUID)
        case createCard(boardID: UUID)
        case patchCard(cardID: UUID)
        case deleteCard(UUID)
        case moveCard(cardID: UUID)
    }

    // MARK: - Protocol conformance

    func listBoards() async throws -> [BoardSummaryDTO] {
        calls.append(.listBoards)
        return try listBoardsResult.get()
    }

    func board(_ id: UUID) async throws -> BoardDTO {
        calls.append(.board(id))
        return try boardResult.get()
    }

    func version(_ id: UUID) async throws -> BoardVersionDTO {
        calls.append(.version(id))
        return try versionResult.get()
    }

    func createColumn(boardID: UUID, title: String) async throws -> BoardDTO {
        calls.append(.createColumn(boardID: boardID, title: title))
        return try createColumnResult.get()
    }

    func patchColumn(boardID: UUID, columnID: UUID, title: String) async throws -> BoardDTO {
        calls.append(.patchColumn(boardID: boardID, columnID: columnID, title: title))
        return try patchColumnResult.get()
    }

    func deleteColumn(boardID: UUID, columnID: UUID) async throws -> BoardDTO {
        calls.append(.deleteColumn(boardID: boardID, columnID: columnID))
        return try deleteColumnResult.get()
    }

    func createCard(boardID: UUID, _ req: CardCreateRequest) async throws -> CardDTO {
        calls.append(.createCard(boardID: boardID))
        return try createCardResult.get()
    }

    func patchCard(cardID: UUID, _ req: CardPatchRequest) async throws -> CardDTO {
        calls.append(.patchCard(cardID: cardID))
        return try patchCardResult.get()
    }

    func deleteCard(cardID: UUID) async throws {
        calls.append(.deleteCard(cardID))
        if let deleteCardError { throw deleteCardError }
    }

    func moveCard(cardID: UUID, _ req: CardMoveRequest) async throws -> CardDTO {
        calls.append(.moveCard(cardID: cardID))
        return try moveCardResult.get()
    }
}

// MARK: - Stub factories

extension BoardDTO {
    static func stub(
        id: UUID = UUID(),
        title: String = "Test Board",
        version: Int64 = 1,
        columns: [ColumnDTO] = []
    ) -> BoardDTO {
        BoardDTO(id: id, title: title, version: version, columns: columns)
    }
}

extension ColumnDTO {
    static func stub(
        id: UUID = UUID(),
        title: String = "Test Column",
        rank: String = "a",
        cards: [CardDTO] = []
    ) -> ColumnDTO {
        ColumnDTO(id: id, title: title, rank: rank, cards: cards)
    }
}

extension CardDTO {
    static func stub(
        id: UUID = UUID(),
        columnID: UUID = UUID(),
        title: String = "Test Card",
        body: String? = nil,
        priority: CardPriority? = nil,
        dueAt: Date? = nil,
        rank: String = "a",
        updatedAt: Date? = nil
    ) -> CardDTO {
        CardDTO(id: id, columnID: columnID, title: title, body: body,
                priority: priority, dueAt: dueAt, rank: rank, updatedAt: updatedAt)
    }
}
