// LuminaVaultClient/LuminaVaultClient/API/Sessions/SessionsHTTPClient.swift
//
// HER-245 — GET /v1/sessions. Server endpoint may not be live yet —
// `list()` treats 404 as a successful empty response so the UI shows
// its empty state until the server-side stub ships.

import Foundation
import LuminaVaultShared

enum SessionsEndpoints {
    struct List: Endpoint {
        typealias Response = SessionListResponse
        let limit: Int?
        var path: String {
            guard let limit else { return "/v1/sessions" }
            return "/v1/sessions?limit=\(limit)"
        }
        var method: HTTPMethod { .get }
    }
}

protocol SessionsClientProtocol: Sendable {
    func list(limit: Int?) async throws -> SessionListResponse
}

final class SessionsHTTPClient: SessionsClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func list(limit: Int? = 50) async throws -> SessionListResponse {
        do {
            return try await client.execute(SessionsEndpoints.List(limit: limit))
        } catch APIError.httpError(let status, _) where status == 404 {
            return SessionListResponse(sessions: [], nextCursor: nil)
        }
    }
}
