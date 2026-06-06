// LuminaVaultClient/LuminaVaultClient/API/Providers/ProvidersEndpoints.swift
//
// HER-252 — server contract:
//   GET    /v1/me/providers                      -> ProviderCredentialsListResponse
//   PUT    /v1/me/providers/{provider}           -> ProviderCredentialDTO
//   DELETE /v1/me/providers/{provider}           -> 204
//   POST   /v1/me/providers/{provider}/test      -> ProviderTestResponse (200) or 502 w/ stable code

import Foundation
import LuminaVaultShared

enum ProvidersEndpoints {
    struct List: Endpoint {
        typealias Response = ProviderCredentialsListResponse
        var path: String { "/v1/me/providers" }
        var method: HTTPMethod { .get }
    }

    struct Put: Endpoint {
        typealias Response = ProviderCredentialDTO
        let provider: ProviderID
        let request: ProviderCredentialPutRequest
        var path: String { "/v1/me/providers/\(provider.rawValue)" }
        var method: HTTPMethod { .put }
        var body: (any Encodable)? { request }
    }

    struct Delete: Endpoint {
        typealias Response = EmptyResponse
        let provider: ProviderID
        var path: String { "/v1/me/providers/\(provider.rawValue)" }
        var method: HTTPMethod { .delete }
    }

    struct Test: Endpoint {
        typealias Response = ProviderTestResponse
        let provider: ProviderID
        var path: String { "/v1/me/providers/\(provider.rawValue)/test" }
        var method: HTTPMethod { .post }
    }

    /// Live model list — fetched from the provider's `/v1/models` when the
    /// provider is OpenAI-compatible, else the offline catalog. Always 200.
    struct Models: Endpoint {
        typealias Response = ProviderModelsResponse
        let provider: ProviderID
        var path: String { "/v1/me/providers/\(provider.rawValue)/models" }
        var method: HTTPMethod { .get }
    }

    // Round-robin credential pool.
    struct ListPool: Endpoint {
        typealias Response = ProviderPoolListResponse
        let provider: ProviderID
        var path: String { "/v1/me/providers/\(provider.rawValue)/pool" }
        var method: HTTPMethod { .get }
    }

    struct AddPool: Endpoint {
        typealias Response = ProviderPoolKeyDTO
        let provider: ProviderID
        let request: ProviderPoolAddRequest
        var path: String { "/v1/me/providers/\(provider.rawValue)/pool" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    struct DeletePool: Endpoint {
        typealias Response = EmptyResponse
        let provider: ProviderID
        let keyID: UUID
        var path: String { "/v1/me/providers/\(provider.rawValue)/pool/\(keyID.uuidString.lowercased())" }
        var method: HTTPMethod { .delete }
    }
}
