// LuminaVaultClient/LuminaVaultClient/API/Hermes/HermesRunsClient.swift
//
// Hermes Companion Phase 1 — BaseHTTPClient-backed `/v1/hermes/runs`.
//
// The live feed rides `BaseHTTPClient.executeStreamWithRefresh`, the same
// transport chat's reply stream uses, so there is exactly one SSE frame
// parser in the app (`SSEFrameParser`, byte-level, blank-line framed).

import Foundation
import LuminaVaultShared

protocol HermesRunsClientProtocol: Sendable {
    func start(_ request: HermesRunStartRequest) async throws -> HermesRunDTO
    func list(limit: Int?) async throws -> [HermesRunDTO]
    func get(_ runID: UUID) async throws -> HermesRunDTO
    func approve(_ runID: UUID, choice: HermesApprovalChoice) async throws -> HermesRunDTO
    func stop(_ runID: UUID) async throws -> HermesRunDTO
    /// Replay-then-live event feed. `after` is the highest `seq` already
    /// held; 0 replays the run from its first event.
    func events(_ runID: UUID, after: Int) -> AsyncThrowingStream<HermesRunEventDTO, any Error>
}

final class HermesRunsHTTPClient: HermesRunsClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func start(_ request: HermesRunStartRequest) async throws -> HermesRunDTO {
        try await client.execute(HermesRunsEndpoints.Start(request: request))
    }

    func list(limit: Int? = 20) async throws -> [HermesRunDTO] {
        try await client.execute(HermesRunsEndpoints.List(limit: limit)).runs
    }

    func get(_ runID: UUID) async throws -> HermesRunDTO {
        try await client.execute(HermesRunsEndpoints.Get(runID: runID))
    }

    func approve(_ runID: UUID, choice: HermesApprovalChoice) async throws -> HermesRunDTO {
        try await client.execute(
            HermesRunsEndpoints.Approve(runID: runID, request: HermesRunApprovalRequest(choice: choice))
        )
    }

    func stop(_ runID: UUID) async throws -> HermesRunDTO {
        try await client.execute(HermesRunsEndpoints.Stop(runID: runID))
    }

    func events(_ runID: UUID, after: Int) -> AsyncThrowingStream<HermesRunEventDTO, any Error> {
        client.executeStreamWithRefresh(HermesRunsEndpoints.Events(runID: runID, after: after))
    }
}
