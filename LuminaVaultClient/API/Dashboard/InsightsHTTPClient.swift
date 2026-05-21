// LuminaVaultClient/LuminaVaultClient/API/Dashboard/InsightsHTTPClient.swift
//
// HER-244 — BaseHTTPClient-backed implementation of InsightsClientProtocol.

import Foundation
import LuminaVaultShared

protocol InsightsClientProtocol: Sendable {
    func list(section: InsightSection?, limit: Int?) async throws -> InsightListResponse
}

final class InsightsHTTPClient: InsightsClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func list(section: InsightSection? = nil, limit: Int? = nil) async throws -> InsightListResponse {
        try await client.execute(InsightsEndpoints.List(section: section, limit: limit))
    }
}
