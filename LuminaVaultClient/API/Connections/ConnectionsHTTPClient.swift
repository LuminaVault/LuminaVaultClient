// LuminaVaultClient/LuminaVaultClient/API/Connections/ConnectionsHTTPClient.swift
import Foundation

protocol ConnectionsClientProtocol: Sendable {
    func summary() async throws -> ConnectionsSummaryResponse
    func testAll() async throws -> ConnectionsTestAllResponse
    func events(limit: Int) async throws -> ConnectionDiagnosticEventsResponse
}

final class ConnectionsHTTPClient: ConnectionsClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) {
        self.client = client
    }

    func summary() async throws -> ConnectionsSummaryResponse {
        try await client.execute(ConnectionsEndpoints.Summary())
    }

    func testAll() async throws -> ConnectionsTestAllResponse {
        try await client.execute(ConnectionsEndpoints.TestAll())
    }

    func events(limit: Int = 30) async throws -> ConnectionDiagnosticEventsResponse {
        try await client.execute(ConnectionsEndpoints.Events(limit: limit))
    }
}
