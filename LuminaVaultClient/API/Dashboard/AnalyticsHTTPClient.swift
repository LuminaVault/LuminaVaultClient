// LuminaVaultClient/LuminaVaultClient/API/Dashboard/AnalyticsHTTPClient.swift
//
// HER-Insights — GET /v1/analytics/usage-summary. Month-to-date LLM +
// embedding token usage, sessions, and a coarse cost estimate. Backs the
// Home "Insights" card.

import Foundation
import LuminaVaultShared

protocol AnalyticsClientProtocol: Sendable {
    func usageSummary() async throws -> UsageSummaryResponse
}

enum AnalyticsEndpoints {
    struct UsageSummary: Endpoint {
        typealias Response = UsageSummaryResponse
        var path: String { "/v1/analytics/usage-summary" }
        var method: HTTPMethod { .get }
    }
}

final class AnalyticsHTTPClient: AnalyticsClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func usageSummary() async throws -> UsageSummaryResponse {
        try await client.execute(AnalyticsEndpoints.UsageSummary())
    }
}
