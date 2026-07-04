// LuminaVaultClient/LuminaVaultClientTests/HermesGatewayDetailViewSnapshotTests.swift
//
// HER-241 — image snapshots for the per-gateway detail/edit screen.
// 3 cases × 2 schemes = 6 baselines.

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient
@testable import LuminaVaultShared

@MainActor
final class HermesGatewayDetailViewSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)
        isRecording = false
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    private final class StubHermesGatewaysClient: HermesGatewaysClientProtocol, @unchecked Sendable {
        let getResult: Result<HermesGatewayCatalogEntry, Error>
        init(getResult: Result<HermesGatewayCatalogEntry, Error>) {
            self.getResult = getResult
        }
        func list() async throws -> HermesGatewaysListResponse {
            HermesGatewaysListResponse(items: [try getResult.get()])
        }
        func get(_: HermesGatewayID) async throws -> HermesGatewayCatalogEntry { try getResult.get() }
        func upsert(_: HermesGatewayID, _: HermesGatewayPutRequest) async throws -> HermesGatewayCatalogEntry { try getResult.get() }
        func delete(_: HermesGatewayID) async throws {}
        func test(_: HermesGatewayID) async throws -> HermesGatewayTestResponse {
            HermesGatewayTestResponse(ok: true, verifiedAt: Date())
        }

        // Actuation + WhatsApp — not exercised by snapshot tests.
        func startApply() async throws -> StartHermesGatewayApplyResponse { throw URLError(.unsupportedURL) }
        func applyStatus(_ jobID: UUID) async throws -> HermesGatewayApplyJobStatus { throw URLError(.unsupportedURL) }
        func applyStream(_ jobID: UUID) -> AsyncThrowingStream<HermesGatewayApplyEvent, any Error> {
            AsyncThrowingStream { _ in }
        }
        func startWhatsAppPair() async throws -> StartWhatsAppPairResponse { StartWhatsAppPairResponse(sessionID: UUID()) }
        func whatsAppPairStream(_ sessionID: UUID) -> AsyncThrowingStream<HermesWhatsAppPairEvent, any Error> {
            AsyncThrowingStream { _ in }
        }
        func unlinkWhatsApp() async throws -> HermesGatewayCatalogEntry { try getResult.get() }

        // Photon (new pairing kind)
        func startPhotonSetup() async throws -> StartPhotonSetupResponse { StartPhotonSetupResponse(sessionID: UUID()) }
        func photonSetupPhone(sessionID: UUID, phone: String) async throws {}
        func photonSetupStream(_ sessionID: UUID) -> AsyncThrowingStream<HermesPhotonSetupEvent, any Error> {
            AsyncThrowingStream { _ in }
        }
    }

    private static func telegramEntry(status: HermesGatewayStatus, hasConfig: Bool) -> HermesGatewayCatalogEntry {
        HermesGatewayCatalogEntry(
            id: .telegram,
            displayName: "Telegram",
            iconSlug: "telegram",
            description: "Chat with Lumina from Telegram via a bot you control.",
            requiredFields: [
                HermesGatewayField(
                    key: "bot_token",
                    label: "Bot token",
                    placeholder: "123456:ABC-DEF…",
                    kind: .secret,
                    isRequired: true,
                ),
            ],
            status: status,
            hasConfig: hasConfig,
            verifiedAt: status == .verified ? Date(timeIntervalSince1970: 1_700_000_000) : nil,
            lastFailureCode: nil,
        )
    }

    private func makeView(
        entry: HermesGatewayCatalogEntry,
        prefillValues: [String: String] = [:],
        save: HermesGatewayDetailViewModel.SaveOutcome = .idle,
    ) -> some View {
        let client = StubHermesGatewaysClient(getResult: .success(entry))
        let vm = HermesGatewayDetailViewModel(gatewayID: entry.id, client: client)
        vm.entry = entry
        vm.loadingState = .ready
        vm.values = prefillValues.isEmpty
            ? Dictionary(uniqueKeysWithValues: entry.requiredFields.map { ($0.key, "") })
            : prefillValues
        vm.save = save
        return NavigationStack {
            HermesGatewayDetailView(gatewayID: entry.id, client: client)
        }
        .transaction { $0.disablesAnimations = true }
    }

    // MARK: - Cases

    func testEmptyFormDark() {
        snap(makeView(entry: Self.telegramEntry(status: .notConfigured, hasConfig: false)),
             scheme: .dark, named: "iPhone13Pro-empty-form-dark")
    }

    func testEmptyFormLight() {
        snap(makeView(entry: Self.telegramEntry(status: .notConfigured, hasConfig: false)),
             scheme: .light, named: "iPhone13Pro-empty-form-light")
    }

    func testSavedReachableDark() {
        snap(
            makeView(
                entry: Self.telegramEntry(status: .verified, hasConfig: true),
                prefillValues: ["bot_token": "•••••••••••••"],
                save: .saved(verifyOk: true, errorCode: nil),
            ),
            scheme: .dark, named: "iPhone13Pro-saved-reachable-dark",
        )
    }

    func testSavedReachableLight() {
        snap(
            makeView(
                entry: Self.telegramEntry(status: .verified, hasConfig: true),
                prefillValues: ["bot_token": "•••••••••••••"],
                save: .saved(verifyOk: true, errorCode: nil),
            ),
            scheme: .light, named: "iPhone13Pro-saved-reachable-light",
        )
    }

    func testSavedUnreachableDark() {
        snap(
            makeView(
                entry: Self.telegramEntry(status: .configured, hasConfig: true),
                prefillValues: ["bot_token": "•••••••••••••"],
                save: .saved(verifyOk: false, errorCode: "hermes_unreachable:dns"),
            ),
            scheme: .dark, named: "iPhone13Pro-saved-unreachable-dark",
        )
    }

    func testSavedUnreachableLight() {
        snap(
            makeView(
                entry: Self.telegramEntry(status: .configured, hasConfig: true),
                prefillValues: ["bot_token": "•••••••••••••"],
                save: .saved(verifyOk: false, errorCode: "hermes_unreachable:dns"),
            ),
            scheme: .light, named: "iPhone13Pro-saved-unreachable-light",
        )
    }

    private func snap(_ view: some View, scheme: UIUserInterfaceStyle, named: String) {
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: scheme),
            ),
            named: named,
        )
    }
}
