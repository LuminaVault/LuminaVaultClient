// LuminaVaultClient/LuminaVaultClient/API/Suggestions/SuggestionsHTTPClient.swift
// HER-37: BaseHTTPClient-backed implementation of SuggestionsClientProtocol.
import Foundation

final class SuggestionsHTTPClient: SuggestionsClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func list() async throws -> SuggestionsResponse {
        try await client.execute(SuggestionsEndpoints.List())
    }
}
