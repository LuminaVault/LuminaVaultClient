// LuminaVaultClient/LuminaVaultClient/API/News/NewsTickerHTTPClient.swift
//
// The first-party news-ticker plugin's surface:
//   GET /v1/news/ticker?limit=   -> NewsTickerResponse
// 404 plugin_not_installed / 409 plugin_disabled mean "no strip"; the plugin
// lifecycle itself lives on /v1/plugins.

import Foundation
import LuminaVaultShared

protocol NewsTickerClientProtocol: Sendable {
    func ticker(limit: Int) async throws -> NewsTickerResponse
}

enum NewsTickerEndpoints {
    struct Get: Endpoint {
        typealias Response = NewsTickerResponse
        let limit: Int
        var path: String { "/v1/news/ticker?limit=\(limit)" }
        var method: HTTPMethod { .get }
        /// A passive strip: a 402 must never slide a paywall over Home.
        var presentsPaywallOn402: Bool { false }
    }
}

final class NewsTickerHTTPClient: NewsTickerClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func ticker(limit: Int = 20) async throws -> NewsTickerResponse {
        try await client.execute(NewsTickerEndpoints.Get(limit: limit))
    }
}
