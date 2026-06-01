// LuminaVaultClient/LuminaVaultClient/API/Achievements/AchievementsHTTPClient.swift
//
// Read-only client for the achievements surface. The backend owns all
// mutation (counters move fire-and-forget from controller hot-paths), so the
// client only reads:
//   GET /v1/achievements         → full catalog + per-tenant progress
//   GET /v1/achievements/recent  → latest unlocks (for the "Recent" strip)
// DTOs are imported from LuminaVaultShared — never redefined here.

import Foundation
import LuminaVaultShared

protocol AchievementsClientProtocol: Sendable {
    func list() async throws -> AchievementsListResponse
    func recent(limit: Int) async throws -> AchievementsRecentResponse
}

enum AchievementsEndpoints {
    struct Get: Endpoint {
        typealias Response = AchievementsListResponse
        var path: String { "/v1/achievements" }
        var method: HTTPMethod { .get }
    }

    struct Recent: Endpoint {
        typealias Response = AchievementsRecentResponse
        let limit: Int
        var path: String {
            var components = URLComponents()
            components.path = "/v1/achievements/recent"
            components.queryItems = [.init(name: "limit", value: String(limit))]
            return components.path + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
        }

        var method: HTTPMethod { .get }
    }
}

final class AchievementsHTTPClient: AchievementsClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func list() async throws -> AchievementsListResponse {
        try await client.execute(AchievementsEndpoints.Get())
    }

    func recent(limit: Int = 10) async throws -> AchievementsRecentResponse {
        try await client.execute(AchievementsEndpoints.Recent(limit: limit))
    }
}
