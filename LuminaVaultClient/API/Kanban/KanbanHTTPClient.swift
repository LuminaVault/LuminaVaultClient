// LuminaVaultClient/LuminaVaultClient/API/Kanban/KanbanHTTPClient.swift
//
// Concrete KanbanClientProtocol backed by BaseHTTPClient.

import Foundation
import LuminaVaultShared

final class KanbanHTTPClient: KanbanClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func listBoards() async throws -> [BoardSummaryDTO] {
        try await client.execute(KanbanEndpoints.ListBoards())
    }

    func board(_ id: UUID) async throws -> BoardDTO {
        try await client.execute(KanbanEndpoints.GetBoard(id: id))
    }

    func version(_ id: UUID) async throws -> BoardVersionDTO {
        try await client.execute(KanbanEndpoints.GetVersion(id: id))
    }

    func createColumn(boardID: UUID, title: String) async throws -> BoardDTO {
        try await client.execute(KanbanEndpoints.CreateColumn(boardID: boardID, title: title))
    }

    func patchColumn(boardID: UUID, columnID: UUID, title: String) async throws -> BoardDTO {
        try await client.execute(KanbanEndpoints.PatchColumn(boardID: boardID, columnID: columnID, title: title))
    }

    func deleteColumn(boardID: UUID, columnID: UUID) async throws -> BoardDTO {
        try await client.execute(KanbanEndpoints.DeleteColumn(boardID: boardID, columnID: columnID))
    }

    func createCard(boardID: UUID, _ req: CardCreateRequest) async throws -> CardDTO {
        try await client.execute(KanbanEndpoints.CreateCard(boardID: boardID, request: req))
    }

    func patchCard(cardID: UUID, _ req: CardPatchRequest) async throws -> CardDTO {
        try await client.execute(KanbanEndpoints.PatchCard(cardID: cardID, request: req))
    }

    func deleteCard(cardID: UUID) async throws {
        _ = try await client.execute(KanbanEndpoints.DeleteCard(cardID: cardID))
    }

    func moveCard(cardID: UUID, _ req: CardMoveRequest) async throws -> CardDTO {
        try await client.execute(KanbanEndpoints.MoveCard(cardID: cardID, request: req))
    }

    func promoteCard(cardID: UUID, _ req: CardPromoteRequest) async throws -> SkillDTO {
        try await client.execute(KanbanEndpoints.PromoteCard(cardID: cardID, request: req))
    }
}
