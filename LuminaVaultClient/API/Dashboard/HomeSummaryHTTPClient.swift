// LuminaVaultClient/LuminaVaultClient/API/Dashboard/HomeSummaryHTTPClient.swift
//
// HER-Home — GET /v1/dashboard/home. One-shot counts (skills, jobs,
// reminders, todos, projects, insights) + the active Hermes profile, so the
// Home dashboard renders every card from a single request.

import Foundation
import LuminaVaultShared

protocol HomeSummaryClientProtocol: Sendable {
    func summary() async throws -> HomeSummaryResponse
}

enum HomeSummaryEndpoints {
    struct Get: Endpoint {
        typealias Response = HomeSummaryResponse
        var path: String { "/v1/dashboard/home" }
        var method: HTTPMethod { .get }
    }
}

final class HomeSummaryHTTPClient: HomeSummaryClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func summary() async throws -> HomeSummaryResponse {
        try await client.execute(HomeSummaryEndpoints.Get())
    }
}
