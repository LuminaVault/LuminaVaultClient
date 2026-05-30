// LuminaVaultClient/LuminaVaultClient/API/System/SystemHermesHTTPClient.swift
//
// HER-330 — concrete client for the owner-only Hermes self-update routes,
// backed by `BaseHTTPClient`. Mirrors `HermesGatewaysHTTPClient`.

import Foundation
import LuminaVaultShared

final class SystemHermesHTTPClient: Sendable {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func version() async throws -> HermesVersionInfo {
        try await client.execute(SystemHermesEndpoints.Version()).info
    }

    func startUpdate(targetTag: String?) async throws -> StartHermesUpdateResponse {
        try await client.execute(
            SystemHermesEndpoints.Start(request: StartHermesUpdateRequest(targetTag: targetTag)),
        )
    }

    /// Most recent in-flight (or last) job, for reconnect. Returns `nil` when
    /// the server reports no job (404).
    func currentJob() async throws -> HermesUpdateJobStatus? {
        do {
            return try await client.execute(SystemHermesEndpoints.Current()).status
        } catch let APIError.httpError(statusCode, _) where statusCode == 404 {
            return nil
        }
    }

    func jobStatus(_ jobID: UUID) async throws -> HermesUpdateJobStatus {
        try await client.execute(SystemHermesEndpoints.Status(jobID: jobID)).status
    }

    func rollback(_ jobID: UUID) async throws -> StartHermesUpdateResponse {
        try await client.execute(SystemHermesEndpoints.Rollback(jobID: jobID))
    }

    func stream(_ jobID: UUID) -> AsyncThrowingStream<HermesUpdateEvent, any Error> {
        client.executeStreamWithRefresh(SystemHermesEndpoints.Stream(jobID: jobID))
    }
}
