// LuminaVaultClient/LuminaVaultClient/API/Settings/SettingsHTTPClient.swift
//
// HER-218 — Settings client backed by `BaseHTTPClient`. The `get` path
// converts a 404 into `nil` to keep the empty/configured state machine
// explicit in the ViewModel.

import Foundation

final class SettingsHTTPClient: SettingsClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func getHermesConfig() async throws -> HermesConfigGetResponse? {
        do {
            return try await client.execute(SettingsEndpoints.GetHermesConfig())
        } catch APIError.httpError(let status, _) where status == 404 {
            return nil
        }
    }

    func putHermesConfig(baseUrl: String, authHeader: String?) async throws -> HermesConfigGetResponse {
        try await client.execute(SettingsEndpoints.PutHermesConfig(baseUrl: baseUrl, authHeader: authHeader))
    }

    func deleteHermesConfig() async throws {
        _ = try await client.execute(SettingsEndpoints.DeleteHermesConfig())
    }

    func testHermesConfig() async throws -> HermesConfigTestResponse {
        try await client.execute(SettingsEndpoints.TestHermesConfig())
    }
}
