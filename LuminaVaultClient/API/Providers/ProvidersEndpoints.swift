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
}
