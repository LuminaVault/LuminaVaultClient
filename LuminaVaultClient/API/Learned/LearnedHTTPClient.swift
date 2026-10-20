// LuminaVaultClient/LuminaVaultClient/API/Learned/LearnedHTTPClient.swift
//
// BaseHTTPClient-backed `LearnedClientProtocol`. Built by
// `AppState.makeLearnedClient()`.

import Foundation
import LuminaVaultShared

final class LearnedHTTPClient: LearnedClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) {
        self.client = client
    }

    func learned(since: Date?) async throws -> LearnedDigestResponse {
        try await client.execute(LearnedEndpoints.Get(since: since))
    }
}
