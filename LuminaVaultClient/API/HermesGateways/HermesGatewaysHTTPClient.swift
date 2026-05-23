// LuminaVaultClient/LuminaVaultClient/API/HermesGateways/HermesGatewaysHTTPClient.swift
//
// HER-241 — concrete `HermesGatewaysClientProtocol` backed by
// `BaseHTTPClient`.

import Foundation
import LuminaVaultShared

final class HermesGatewaysHTTPClient: HermesGatewaysClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func list() async throws -> HermesGatewaysListResponse {
        try await client.execute(HermesGatewaysEndpoints.List())
    }

    func get(_ id: HermesGatewayID) async throws -> HermesGatewayCatalogEntry {
        try await client.execute(HermesGatewaysEndpoints.Get(id: id))
    }

    func upsert(_ id: HermesGatewayID, _ body: HermesGatewayPutRequest) async throws -> HermesGatewayCatalogEntry {
        try await client.execute(HermesGatewaysEndpoints.Put(id: id, request: body))
    }

    func delete(_ id: HermesGatewayID) async throws {
        _ = try await client.execute(HermesGatewaysEndpoints.Delete(id: id))
    }

    func test(_ id: HermesGatewayID) async throws -> HermesGatewayTestResponse {
        try await client.execute(HermesGatewaysEndpoints.Test(id: id))
    }
}
