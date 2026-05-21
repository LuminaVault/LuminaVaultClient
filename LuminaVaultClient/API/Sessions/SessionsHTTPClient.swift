// LuminaVaultClient/LuminaVaultClient/API/Sessions/SessionsHTTPClient.swift
//
// HER-245 — GET /v1/sessions. HER-259 made it real on the server;
// HER-261 adds the optional `?workspace=<uuid>` filter to scope a
// read to a single Workspace (= Space). 404 still maps to empty as a
// graceful fallback while older servers roll out.

import Foundation
import LuminaVaultShared

enum SessionsEndpoints {
    struct List: Endpoint {
        typealias Response = SessionListResponse
        let limit: Int?
        let workspaceID: UUID?

        var path: String {
            var components = URLComponents()
            components.path = "/v1/sessions"
            var items: [URLQueryItem] = []
            if let limit {
                items.append(.init(name: "limit", value: String(limit)))
            }
            if let workspaceID {
                items.append(.init(name: "workspace", value: workspaceID.uuidString))
            }
            if !items.isEmpty { components.queryItems = items }
            return components.path + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
        }

        var method: HTTPMethod { .get }
    }
}

protocol SessionsClientProtocol: Sendable {
    func list(limit: Int?, workspaceID: UUID?) async throws -> SessionListResponse
}

final class SessionsHTTPClient: SessionsClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func list(limit: Int? = 50, workspaceID: UUID? = nil) async throws -> SessionListResponse {
        do {
            return try await client.execute(SessionsEndpoints.List(limit: limit, workspaceID: workspaceID))
        } catch APIError.httpError(let status, _) where status == 404 {
            return SessionListResponse(sessions: [], nextCursor: nil)
        }
    }
}
