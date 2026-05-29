// LuminaVaultClient/LuminaVaultClient/API/Dashboard/DashboardProfileHTTPClient.swift
//
// BaseHTTPClient-backed implementation of DashboardProfileClientProtocol.

import Foundation
import LuminaVaultShared

protocol DashboardProfileClientProtocol: Sendable {
    func profile() async throws -> DashboardProfileResponse
}

final class DashboardProfileHTTPClient: DashboardProfileClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func profile() async throws -> DashboardProfileResponse {
        try await client.execute(DashboardProfileEndpoints.Get())
    }
}
