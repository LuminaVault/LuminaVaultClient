// LuminaVaultClient/LuminaVaultClient/API/Dashboard/ActivityFeedHTTPClient.swift
//
// Command Center — GET /v1/dashboard/activity. Unified recent-activity
// stream (conversations, memories, achievements, skill runs) backing the
// Home "Activity" feed.

import Foundation
import LuminaVaultShared

protocol ActivityFeedClientProtocol: Sendable {
    func activity(limit: Int) async throws -> ActivityFeedResponse
}

enum ActivityFeedEndpoints {
    struct Get: Endpoint {
        typealias Response = ActivityFeedResponse
        let limit: Int
        var path: String { "/v1/dashboard/activity?limit=\(limit)" }
        var method: HTTPMethod { .get }
    }
}

final class ActivityFeedHTTPClient: ActivityFeedClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func activity(limit: Int) async throws -> ActivityFeedResponse {
        try await client.execute(ActivityFeedEndpoints.Get(limit: limit))
    }
}
