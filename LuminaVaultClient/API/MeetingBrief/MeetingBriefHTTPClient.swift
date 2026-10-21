// LuminaVaultClient/LuminaVaultClient/API/MeetingBrief/MeetingBriefHTTPClient.swift
//
// BaseHTTPClient-backed `MeetingBriefClientProtocol`. Built by
// `AppState.makeMeetingBriefClient()`.

import Foundation
import LuminaVaultShared

final class MeetingBriefHTTPClient: MeetingBriefClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) {
        self.client = client
    }

    func brief(eventID: UUID) async throws -> MeetingBriefResponse {
        try await client.execute(MeetingBriefEndpoints.Get(eventID: eventID))
    }
}
