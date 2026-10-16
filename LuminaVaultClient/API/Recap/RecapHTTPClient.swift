// LuminaVaultClient/LuminaVaultClient/API/Recap/RecapHTTPClient.swift
//
// BaseHTTPClient-backed `RecapClientProtocol`. Built by
// `AppState.makeRecapClient()`.

import Foundation
import LuminaVaultShared

final class RecapHTTPClient: RecapClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) {
        self.client = client
    }

    func recap(range: AnalyticsRange) async throws -> MeRecapResponse {
        try await client.execute(RecapEndpoints.Get(range: range))
    }
}
