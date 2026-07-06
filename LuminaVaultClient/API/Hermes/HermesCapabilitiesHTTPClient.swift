// LuminaVaultClient/LuminaVaultClient/API/Hermes/HermesCapabilitiesHTTPClient.swift
//
// P3 — GET /v1/me/hermes/capabilities. Reports what the tenant's connected
// Hermes exposes per settings domain so panes gate on live/read_only/
// unsupported. Managed tenants (no BYO override) report every domain as
// `.managed`.

import Foundation
import LuminaVaultShared

protocol HermesCapabilitiesClientProtocol: Sendable {
    func get(refresh: Bool) async throws -> HermesCapabilitiesResponse
}

extension HermesCapabilitiesClientProtocol {
    func get() async throws -> HermesCapabilitiesResponse { try await get(refresh: false) }
}

final class HermesCapabilitiesHTTPClient: HermesCapabilitiesClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func get(refresh: Bool) async throws -> HermesCapabilitiesResponse {
        do {
            return try await client.execute(HermesCapabilitiesEndpoints.Get(refresh: refresh))
        } catch APIError.httpError(let status, _) where status == 404 {
            // Older server without the endpoint — assume managed so panes
            // stay fully enabled rather than locking the user out.
            return HermesCapabilitiesResponse(capabilities: .managedDefault, checkedAt: nil)
        }
    }
}
