// LuminaVaultClient/LuminaVaultClient/API/Apple/AppleConsentHTTPClient.swift
//
// Apple Ecosystem Integration P0 — per-domain data-access consent.
//   GET /v1/apple/consent · PUT /v1/apple/consent

import Foundation
import LuminaVaultShared

protocol AppleConsentClientProtocol: Sendable {
    func get() async throws -> AppleConsentResponse
    func update(_ request: AppleConsentUpdateRequest) async throws -> AppleConsentResponse
}

enum AppleConsentEndpoints {
    struct Get: Endpoint {
        typealias Response = AppleConsentResponse
        var path: String { "/v1/apple/consent" }
        var method: HTTPMethod { .get }
    }

    struct Put: Endpoint {
        typealias Response = AppleConsentResponse
        let request: AppleConsentUpdateRequest
        var path: String { "/v1/apple/consent" }
        var method: HTTPMethod { .put }
        var body: (any Encodable)? { request }
    }
}

final class AppleConsentHTTPClient: AppleConsentClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func get() async throws -> AppleConsentResponse {
        try await client.execute(AppleConsentEndpoints.Get())
    }

    func update(_ request: AppleConsentUpdateRequest) async throws -> AppleConsentResponse {
        try await client.execute(AppleConsentEndpoints.Put(request: request))
    }
}
