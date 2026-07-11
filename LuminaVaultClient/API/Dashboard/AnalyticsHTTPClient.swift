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

protocol UsageIntelligenceClientProtocol: Sendable {
    func overview(range: AnalyticsRange) async throws -> AnalyticsOverviewResponse
    func models(range: AnalyticsRange) async throws -> ModelEffectivenessResponse
    func record(_ event: AnalyticsEventRequest) async throws
    func updateRecommendation(_ request: AnalyticsRecommendationStateRequest) async throws
}

enum AnalyticsEndpoints {
    struct UsageSummary: Endpoint {
        typealias Response = UsageSummaryResponse
        var path: String { "/v1/analytics/usage-summary" }
        var method: HTTPMethod { .get }
    }

    struct Overview: Endpoint {
        typealias Response = AnalyticsOverviewResponse
        let range: AnalyticsRange
        var path: String { "/v1/analytics/overview?range=\(range.rawValue)&scope=personal" }
        var method: HTTPMethod { .get }
    }

    struct Models: Endpoint {
        typealias Response = ModelEffectivenessResponse
        let range: AnalyticsRange
        var path: String { "/v1/analytics/models?range=\(range.rawValue)&scope=personal" }
        var method: HTTPMethod { .get }
    }

    struct RecordEvent: Endpoint {
        typealias Response = AnalyticsMutationResponse
        let request: AnalyticsEventRequest
        var path: String { "/v1/analytics/events?scope=personal" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    struct RecommendationState: Endpoint {
        typealias Response = AnalyticsMutationResponse
        let request: AnalyticsRecommendationStateRequest
        var path: String { "/v1/analytics/recommendations?scope=personal" }
        var method: HTTPMethod { .patch }
        var body: (any Encodable)? { request }
    }
}

final class AnalyticsHTTPClient: AnalyticsClientProtocol, UsageIntelligenceClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func usageSummary() async throws -> UsageSummaryResponse {
        try await client.execute(AnalyticsEndpoints.UsageSummary())
    }

    func overview(range: AnalyticsRange) async throws -> AnalyticsOverviewResponse {
        try await client.execute(AnalyticsEndpoints.Overview(range: range))
    }

    func models(range: AnalyticsRange) async throws -> ModelEffectivenessResponse {
        try await client.execute(AnalyticsEndpoints.Models(range: range))
    }

    func record(_ event: AnalyticsEventRequest) async throws {
        _ = try await client.execute(AnalyticsEndpoints.RecordEvent(request: event))
    }

    func updateRecommendation(_ request: AnalyticsRecommendationStateRequest) async throws {
        _ = try await client.execute(AnalyticsEndpoints.RecommendationState(request: request))
    }
}
