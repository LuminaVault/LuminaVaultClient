// LuminaVaultClient/LuminaVaultClient/API/Suggestions/SuggestionsEndpoints.swift
// HER-37: GET /v1/me/suggestions.
import Foundation

enum SuggestionsEndpoints {
    struct List: Endpoint {
        typealias Response = SuggestionsResponse
        var path: String { "/v1/me/suggestions" }
        var method: HTTPMethod { .get }
    }
}
