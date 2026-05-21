// LuminaVaultClient/LuminaVaultClient/API/Soul/SoulHTTPClient.swift
//
// HER-250 — GET/PUT /v1/soul wire.

import Foundation
import LuminaVaultShared

enum SoulEndpoints {
    struct Get: Endpoint {
        typealias Response = SoulMdResponse
        var path: String { "/v1/soul" }
        var method: HTTPMethod { .get }
    }

    struct Put: Endpoint {
        typealias Response = SoulMdResponse
        let request: SoulMdPutRequest
        var path: String { "/v1/soul" }
        var method: HTTPMethod { .put }
        var body: (any Encodable)? { request }
    }
}

protocol SoulClientProtocol: Sendable {
    func get() async throws -> SoulMdResponse
    func put(_ body: SoulMdPutRequest) async throws -> SoulMdResponse
}

final class SoulHTTPClient: SoulClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func get() async throws -> SoulMdResponse {
        do {
            return try await client.execute(SoulEndpoints.Get())
        } catch APIError.httpError(let status, _) where status == 404 {
            return SoulMdResponse(body: "", updatedAt: nil)
        }
    }

    func put(_ body: SoulMdPutRequest) async throws -> SoulMdResponse {
        try await client.execute(SoulEndpoints.Put(request: body))
    }
}
