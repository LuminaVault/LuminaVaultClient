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

    func startApply() async throws -> StartHermesGatewayApplyResponse {
        try await client.execute(HermesGatewaysEndpoints.Apply())
    }

    func applyStatus(_ jobID: UUID) async throws -> HermesGatewayApplyJobStatus {
        try await client.execute(HermesGatewaysEndpoints.ApplyStatus(jobID: jobID))
    }

    func applyStream(_ jobID: UUID) -> AsyncThrowingStream<HermesGatewayApplyEvent, any Error> {
        client.executeStreamWithRefresh(HermesGatewaysEndpoints.ApplyStream(jobID: jobID))
    }

    func startWhatsAppPair() async throws -> StartWhatsAppPairResponse {
        try await client.execute(HermesGatewaysEndpoints.StartWhatsAppPair())
    }

    func whatsAppPairStream(_ sessionID: UUID) -> AsyncThrowingStream<HermesWhatsAppPairEvent, any Error> {
        client.executeStreamWithRefresh(HermesGatewaysEndpoints.WhatsAppPairStream(sessionID: sessionID))
    }

    func unlinkWhatsApp() async throws -> HermesGatewayCatalogEntry {
        try await client.execute(HermesGatewaysEndpoints.DeleteWhatsAppSession())
    }

    func startPhotonSetup() async throws -> StartPhotonSetupResponse {
        try await client.execute(HermesGatewaysEndpoints.StartPhotonSetup())
    }

    func photonSetupPhone(sessionID: UUID, phone: String) async throws {
        _ = try await client.execute(HermesGatewaysEndpoints.SubmitPhotonPhone(sessionID: sessionID, phone: phone))
    }

    func photonSetupStream(_ sessionID: UUID) -> AsyncThrowingStream<HermesPhotonSetupEvent, any Error> {
        client.executeStreamWithRefresh(HermesGatewaysEndpoints.PhotonSetupStream(sessionID: sessionID))
    }
}
