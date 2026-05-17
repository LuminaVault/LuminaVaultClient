// LuminaVaultClient/LuminaVaultClient/API/Vault/VaultEndpoints.swift
// HER-35: POST /v1/vault/create + GET /v1/vault/status. Both are
// authenticated (the user has just signed in but has not yet been
// authorized to land on the home screen).
import Foundation

enum VaultEndpoints {
    struct Create: Endpoint {
        typealias Response = VaultStatusResponse
        var path: String { "/v1/vault/create" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { VaultCreateRequest() }
    }

    struct Status: Endpoint {
        typealias Response = VaultStatusResponse
        var path: String { "/v1/vault/status" }
        var method: HTTPMethod { .get }
    }
}
