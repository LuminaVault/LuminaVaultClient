// LuminaVaultClient/LuminaVaultClient/API/Integrations/IntegrationsHTTPClient.swift
//
// HER-240b — `IntegrationsClientProtocol` backed by `BaseHTTPClient`. The
// 401 auto-refresh interceptor (HER-237) covers all four routes.

import Foundation

final class IntegrationsHTTPClient: IntegrationsClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func getXaiStatus() async throws -> XaiStatusResponse {
        try await client.execute(IntegrationsEndpoints.GetXaiStatus())
    }

    func startXaiConnect() async throws -> XaiStartResponse {
        try await client.execute(IntegrationsEndpoints.StartXaiConnect())
    }

    func completeXaiConnect(sessionID: String, callbackURL: String) async throws -> XaiStatusResponse {
        try await client.execute(IntegrationsEndpoints.CompleteXaiConnect(
            sessionID: sessionID,
            callbackURL: callbackURL,
        ))
    }

    func disconnectXai() async throws -> XaiStatusResponse {
        try await client.execute(IntegrationsEndpoints.DisconnectXai())
    }

    // MARK: - Nous Portal subscription

    func getNousStatus() async throws -> NousStatusResponse {
        try await client.execute(IntegrationsEndpoints.GetNousStatus())
    }

    func startNousConnect() async throws -> NousStartResponse {
        try await client.execute(IntegrationsEndpoints.StartNousConnect())
    }

    func completeNousConnect(sessionID: String) async throws -> NousStatusResponse {
        try await client.execute(IntegrationsEndpoints.CompleteNousConnect(sessionID: sessionID))
    }

    func disconnectNous() async throws -> NousStatusResponse {
        try await client.execute(IntegrationsEndpoints.DisconnectNous())
    }
}
