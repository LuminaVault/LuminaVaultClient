// LuminaVaultClient/LuminaVaultClient/API/Kanban/KanbanEndpoints.swift
//
// One Endpoint struct per server route. Server contract:
//   GET    /v1/boards                           -> [BoardSummaryDTO]
//   GET    /v1/boards/{id}                      -> BoardDTO
//   GET    /v1/boards/{id}/version              -> BoardVersionDTO
//   POST   /v1/boards/{boardID}/columns         -> BoardDTO
//   PATCH  /v1/boards/{boardID}/columns/{colID} -> BoardDTO
//   DELETE /v1/boards/{boardID}/columns/{colID} -> BoardDTO
//   POST   /v1/boards/{boardID}/cards           -> CardDTO
//   PATCH  /v1/cards/{cardID}                   -> CardDTO
//   DELETE /v1/cards/{cardID}                   -> 204 No Content
//   POST   /v1/cards/{cardID}/move              -> CardDTO

import Foundation
import LuminaVaultShared

enum KanbanEndpoints {
    private static func versionHeaders(_ version: Int64?) -> [String: String] {
        version.map { ["X-Board-Version": String($0)] } ?? [:]
    }

    struct ListBoards: Endpoint {
        typealias Response = [BoardSummaryDTO]
        var path: String {
            "/v1/boards"
        }

        var method: HTTPMethod {
            .get
        }
    }

    struct GetBoard: Endpoint {
        typealias Response = BoardDTO
        let id: UUID
        var path: String {
            "/v1/boards/\(id)"
        }

        var method: HTTPMethod {
            .get
        }
    }

    struct GetVersion: Endpoint {
        typealias Response = BoardVersionDTO
        let id: UUID
        var path: String {
            "/v1/boards/\(id)/version"
        }

        var method: HTTPMethod {
            .get
        }
    }

    struct CreateColumn: Endpoint {
        typealias Response = BoardDTO
        let boardID: UUID
        let title: String
        let expectedVersion: Int64?
        var path: String {
            "/v1/boards/\(boardID)/columns"
        }

        var method: HTTPMethod {
            .post
        }

        var body: (any Encodable)? {
            ColumnCreateRequest(title: title)
        }

        var additionalHeaders: [String: String] {
            KanbanEndpoints.versionHeaders(expectedVersion)
        }
    }

    struct PatchColumn: Endpoint {
        typealias Response = BoardDTO
        let boardID: UUID
        let columnID: UUID
        let title: String
        let expectedVersion: Int64?
        var path: String {
            "/v1/boards/\(boardID)/columns/\(columnID)"
        }

        var method: HTTPMethod {
            .patch
        }

        var body: (any Encodable)? {
            ColumnPatchRequest(title: title)
        }

        var additionalHeaders: [String: String] {
            KanbanEndpoints.versionHeaders(expectedVersion)
        }
    }

    struct DeleteColumn: Endpoint {
        typealias Response = BoardDTO
        let boardID: UUID
        let columnID: UUID
        let expectedVersion: Int64?
        var path: String {
            "/v1/boards/\(boardID)/columns/\(columnID)"
        }

        var method: HTTPMethod {
            .delete
        }

        var additionalHeaders: [String: String] {
            KanbanEndpoints.versionHeaders(expectedVersion)
        }
    }

    struct CreateCard: Endpoint {
        typealias Response = CardDTO
        let boardID: UUID
        let request: CardCreateRequest
        let expectedVersion: Int64?
        var path: String {
            "/v1/boards/\(boardID)/cards"
        }

        var method: HTTPMethod {
            .post
        }

        var body: (any Encodable)? {
            request
        }

        var additionalHeaders: [String: String] {
            KanbanEndpoints.versionHeaders(expectedVersion)
        }
    }

    struct PatchCard: Endpoint {
        typealias Response = CardDTO
        let cardID: UUID
        let request: CardPatchRequest
        let expectedVersion: Int64?
        var path: String {
            "/v1/cards/\(cardID)"
        }

        var method: HTTPMethod {
            .patch
        }

        var body: (any Encodable)? {
            request
        }

        var additionalHeaders: [String: String] {
            KanbanEndpoints.versionHeaders(expectedVersion)
        }
    }

    struct DeleteCard: Endpoint {
        typealias Response = EmptyResponse
        let cardID: UUID
        let expectedVersion: Int64?
        var path: String {
            "/v1/cards/\(cardID)"
        }

        var method: HTTPMethod {
            .delete
        }

        var additionalHeaders: [String: String] {
            KanbanEndpoints.versionHeaders(expectedVersion)
        }
    }

    struct MoveCard: Endpoint {
        typealias Response = CardDTO
        let cardID: UUID
        let request: CardMoveRequest
        let expectedVersion: Int64?
        var path: String {
            "/v1/cards/\(cardID)/move"
        }

        var method: HTTPMethod {
            .post
        }

        var body: (any Encodable)? {
            request
        }

        var additionalHeaders: [String: String] {
            KanbanEndpoints.versionHeaders(expectedVersion)
        }
    }

    ///   POST   /v1/cards/{cardID}/promote          -> SkillDTO
    struct PromoteCard: Endpoint {
        typealias Response = SkillDTO
        let cardID: UUID
        let request: CardPromoteRequest
        let expectedVersion: Int64?
        var path: String {
            "/v1/cards/\(cardID)/promote"
        }

        var method: HTTPMethod {
            .post
        }

        var body: (any Encodable)? {
            request
        }

        var additionalHeaders: [String: String] {
            KanbanEndpoints.versionHeaders(expectedVersion)
        }
    }
}
