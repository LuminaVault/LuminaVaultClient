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

    // Actuation — apply saved gateways to the running container with progress.
    func startApply() async throws -> StartHermesGatewayApplyResponse
    func applyStatus(_ jobID: UUID) async throws -> HermesGatewayApplyJobStatus
    func applyStream(_ jobID: UUID) -> AsyncThrowingStream<HermesGatewayApplyEvent, any Error>

    // WhatsApp QR pairing — start a session, stream QR + status, unlink.
    func startWhatsAppPair() async throws -> StartWhatsAppPairResponse
    func whatsAppPairStream(_ sessionID: UUID) -> AsyncThrowingStream<HermesWhatsAppPairEvent, any Error>
    func unlinkWhatsApp() async throws -> HermesGatewayCatalogEntry

    // Photon iMessage setup (device code + phone bind for the free path).
    // Mirrors the server routes under /v1/me/hermes-gateways/photon/setup...
    func startPhotonSetup() async throws -> StartPhotonSetupResponse
    func photonSetupPhone(sessionID: UUID, phone: String) async throws
    func photonSetupStream(_ sessionID: UUID) -> AsyncThrowingStream<HermesPhotonSetupEvent, any Error>
}
