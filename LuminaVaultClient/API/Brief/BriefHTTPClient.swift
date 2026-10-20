// LuminaVaultClient/LuminaVaultClient/API/Brief/BriefHTTPClient.swift
//
// BaseHTTPClient-backed `BriefClientProtocol`. Built by
// `AppState.makeBriefClient()`.

import Foundation
import LuminaVaultShared

final class BriefHTTPClient: BriefClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) {
        self.client = client
    }

    func brief(date: String?) async throws -> MeBriefResponse {
        try await client.execute(BriefEndpoints.Get(date: date))
    }

    func feedback(briefID: UUID, cardID: String, action: BriefCardFeedbackAction) async throws {
        _ = try await client.execute(BriefEndpoints.Feedback(briefID: briefID, cardID: cardID, action: action))
    }
}
