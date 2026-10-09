// LuminaVaultClient/LuminaVaultClient/API/Settings/SettingsEndpoints.swift
//
// HER-218 — BYO-Hermes Settings endpoints. Server contract:
//   GET    /v1/settings/hermes        -> HermesConfigGetResponse   (404 = empty state)
//   PUT    /v1/settings/hermes        -> HermesConfigGetResponse
//   DELETE /v1/settings/hermes        -> 204 No Content
//   POST   /v1/settings/hermes/test   -> HermesConfigTestResponse

import Foundation

nonisolated enum SettingsEndpoints {
    nonisolated struct GetHermesConfig: Endpoint {
        typealias Response = HermesConfigGetResponse
        var path: String { "/v1/settings/hermes" }
        var method: HTTPMethod { .get }
    }

    nonisolated struct PutHermesConfig: Endpoint {
        typealias Response = HermesConfigGetResponse
        let baseUrl: String
        let authHeader: String?
        let name: String?
        var path: String { "/v1/settings/hermes" }
        var method: HTTPMethod { .put }
        var body: (any Encodable)? {
            HermesConfigPutRequest(baseUrl: baseUrl, authHeader: authHeader, name: name)
        }
        // Wire is camelCase: the server's HermesConfigController.PutRequest uses
        // the default decoder (no snake conversion), matching LLMPreferences.Put.
        // A `convertToSnakeCase` override here sent `base_url` → server 400
        // "Coding key `baseUrl` not found".
    }

    nonisolated struct DeleteHermesConfig: Endpoint {
        typealias Response = EmptyResponse
        var path: String { "/v1/settings/hermes" }
        var method: HTTPMethod { .delete }
    }

    nonisolated struct TestHermesConfig: Endpoint {
        typealias Response = HermesConfigTestResponse
        var path: String { "/v1/settings/hermes/test" }
        var method: HTTPMethod { .post }
    }
}
