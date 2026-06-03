// LuminaVaultClient/LuminaVaultClient/API/Soul/SoulHTTPClient.swift
//
// HER-250 — GET/PUT/DELETE /v1/soul wire. Contract is the canonical
// `SoulResponse { markdown, updatedAt }` / `SoulPutRequest { markdown }`
// from LuminaVaultShared (matches openapi.yaml). DELETE resets to the
// bootstrap template and returns 204 — callers re-fetch to show it.

import Foundation
import LuminaVaultShared

enum SoulEndpoints {
    struct Get: Endpoint {
        typealias Response = SoulResponse
        var path: String { "/v1/soul" }
        var method: HTTPMethod { .get }
    }

    struct Put: Endpoint {
        typealias Response = SoulResponse
        let request: SoulPutRequest
        var path: String { "/v1/soul" }
        var method: HTTPMethod { .put }
        var body: (any Encodable)? { request }
    }

    struct Delete: Endpoint {
        typealias Response = EmptyResponse
        var path: String { "/v1/soul" }
        var method: HTTPMethod { .delete }
    }
}

protocol SoulClientProtocol: Sendable {
    func get() async throws -> SoulResponse
    func put(_ body: SoulPutRequest) async throws -> SoulResponse
    /// Resets SOUL.md to the bootstrap template (server returns 204).
    func delete() async throws
}

final class SoulHTTPClient: SoulClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func get() async throws -> SoulResponse {
        do {
            return try await client.execute(SoulEndpoints.Get())
        } catch APIError.httpError(let status, _) where status == 404 {
            return SoulResponse(markdown: "", updatedAt: nil)
        }
    }

    func put(_ body: SoulPutRequest) async throws -> SoulResponse {
        try await client.execute(SoulEndpoints.Put(request: body))
    }

    func delete() async throws {
        _ = try await client.execute(SoulEndpoints.Delete())
    }
}
