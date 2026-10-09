// LuminaVaultClient/LuminaVaultClient/API/LLMPreferences/LLMPreferencesEndpoints.swift
//
// HER-252 — server contract:
//   GET /v1/me/preferences/llm -> LLMPreferencesGetResponse (always 200)
//   PUT /v1/me/preferences/llm -> LLMPreferencesGetResponse

import Foundation
import LuminaVaultShared

nonisolated enum LLMPreferencesEndpoints {
    nonisolated struct Get: Endpoint {
        typealias Response = LLMPreferencesGetResponse
        var path: String { "/v1/me/preferences/llm" }
        var method: HTTPMethod { .get }
    }

    nonisolated struct Put: Endpoint {
        typealias Response = LLMPreferencesGetResponse
        let request: LLMPreferencesPutRequest
        var path: String { "/v1/me/preferences/llm" }
        var method: HTTPMethod { .put }
        var body: (any Encodable)? { request }
    }
}

nonisolated enum RouterEndpoints {
    nonisolated struct Profiles: Endpoint {
        typealias Response = RouterProfilesResponse
        var path: String { "/v1/router" }
        var method: HTTPMethod { .get }
    }

    nonisolated struct Catalog: Endpoint {
        typealias Response = RouterCatalogResponse
        var path: String { "/v1/router/catalog" }
        var method: HTTPMethod { .get }
    }

    nonisolated struct Dashboard: Endpoint {
        typealias Response = RouterDashboardResponse
        var path: String { "/v1/router/dashboard" }
        var method: HTTPMethod { .get }
    }

    nonisolated struct UpdateProfile: Endpoint {
        typealias Response = RouterProfileDTO
        let id: UUID
        let request: RouterProfileWriteRequest
        var path: String { "/v1/router/\(id.uuidString)" }
        var method: HTTPMethod { .put }
        var body: (any Encodable)? { request }
    }

    nonisolated struct Bindings: Endpoint {
        typealias Response = RouterBindingsResponse
        var path: String { "/v1/router/bindings" }
        var method: HTTPMethod { .get }
    }

    nonisolated struct PutBinding: Endpoint {
        typealias Response = RouterBindingDTO
        let scope: RouterBindingScope
        let scopeID: String
        let profileID: UUID
        var path: String { "/v1/router/bindings/\(scope.rawValue)/\(scopeID)" }
        var method: HTTPMethod { .put }
        var body: (any Encodable)? { RouterBindingPutRequest(profileID: profileID) }
    }

    nonisolated struct DeleteBinding: Endpoint {
        typealias Response = EmptyResponse
        let scope: RouterBindingScope
        let scopeID: String
        var path: String { "/v1/router/bindings/\(scope.rawValue)/\(scopeID)" }
        var method: HTTPMethod { .delete }
    }
}
