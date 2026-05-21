// LuminaVaultClient/LuminaVaultClient/API/LLMPreferences/LLMPreferencesEndpoints.swift
//
// HER-252 — server contract:
//   GET /v1/me/preferences/llm -> LLMPreferencesGetResponse (always 200)
//   PUT /v1/me/preferences/llm -> LLMPreferencesGetResponse

import Foundation
import LuminaVaultShared

enum LLMPreferencesEndpoints {
    struct Get: Endpoint {
        typealias Response = LLMPreferencesGetResponse
        var path: String { "/v1/me/preferences/llm" }
        var method: HTTPMethod { .get }
    }

    struct Put: Endpoint {
        typealias Response = LLMPreferencesGetResponse
        let request: LLMPreferencesPutRequest
        var path: String { "/v1/me/preferences/llm" }
        var method: HTTPMethod { .put }
        var body: (any Encodable)? { request }
    }
}
