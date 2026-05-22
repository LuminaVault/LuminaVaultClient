// LuminaVaultClient/LuminaVaultClient/API/HermesGateways/HermesGatewaysClientProtocol.swift
//
// HER-241 — per-user Hermes messaging gateway client. The server's
// GET returns one row per supported HermesGatewayID even when the
// user has no stored config; ViewModels read `status == .notConfigured`
// (or `hasConfig == false`) to render the empty state.

import Foundation
import LuminaVaultShared

protocol HermesGatewaysClientProtocol: Sendable {
    func list() async throws -> HermesGatewaysListResponse
    func get(_ id: HermesGatewayID) async throws -> HermesGatewayCatalogEntry
    func upsert(_ id: HermesGatewayID, _ body: HermesGatewayPutRequest) async throws -> HermesGatewayCatalogEntry
    func delete(_ id: HermesGatewayID) async throws
    func test(_ id: HermesGatewayID) async throws -> HermesGatewayTestResponse
}
