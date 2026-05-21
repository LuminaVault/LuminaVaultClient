// LuminaVaultClient/LuminaVaultClient/API/Dashboard/DashboardStatsHTTPClient.swift
//
// HER-244 — BaseHTTPClient-backed implementation of DashboardStatsClientProtocol.

import Foundation
import LuminaVaultShared

protocol DashboardStatsClientProtocol: Sendable {
    func stats() async throws -> DashboardStatsResponse
}

final class DashboardStatsHTTPClient: DashboardStatsClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func stats() async throws -> DashboardStatsResponse {
        try await client.execute(DashboardStatsEndpoints.Get())
    }
}
