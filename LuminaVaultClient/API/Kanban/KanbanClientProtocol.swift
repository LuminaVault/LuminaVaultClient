// LuminaVaultClient/LuminaVaultClient/API/Kanban/KanbanClientProtocol.swift
//
// Kanban board API protocol. Each method maps 1:1 to a server route.
// All mutations return the updated aggregate (BoardDTO or CardDTO) so the
// caller can replace its local copy without a separate GET.

import Foundation
import LuminaVaultShared

protocol KanbanClientProtocol: Sendable {
    func listBoards() async throws -> [BoardSummaryDTO]
    func board(_ id: UUID) async throws -> BoardDTO
    func version(_ id: UUID) async throws -> BoardVersionDTO
    func createColumn(boardID: UUID, title: String) async throws -> BoardDTO
    func patchColumn(boardID: UUID, columnID: UUID, title: String) async throws -> BoardDTO
    func deleteColumn(boardID: UUID, columnID: UUID) async throws -> BoardDTO
    func createCard(boardID: UUID, _ req: CardCreateRequest) async throws -> CardDTO
    func patchCard(cardID: UUID, _ req: CardPatchRequest) async throws -> CardDTO
    func deleteCard(cardID: UUID) async throws
    func moveCard(cardID: UUID, _ req: CardMoveRequest) async throws -> CardDTO
}
