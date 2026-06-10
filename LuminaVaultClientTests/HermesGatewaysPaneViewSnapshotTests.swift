// LuminaVaultClient/LuminaVaultClientTests/HermesGatewaysPaneViewSnapshotTests.swift
//
// HER-241 — image snapshots for the Settings → Messaging Gateways pane.
// 3 cases × 2 schemes = 6 baselines. Records via flipping `isRecording`
// on the first run, then revert (pattern shipped in HER-263).

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient
@testable import LuminaVaultShared

@MainActor
final class HermesGatewaysPaneViewSnapshotTests: XCTestCase {
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
        let listResult: Result<HermesGatewaysListResponse, Error>
        init(listResult: Result<HermesGatewaysListResponse, Error>) {
            self.listResult = listResult
        }
        func list() async throws -> HermesGatewaysListResponse { try listResult.get() }
        func get(_: HermesGatewayID) async throws -> HermesGatewayCatalogEntry {
            try listResult.get().items.first!
        }
        func upsert(_: HermesGatewayID, _: HermesGatewayPutRequest) async throws -> HermesGatewayCatalogEntry {
            try listResult.get().items.first!
        }
        func delete(_: HermesGatewayID) async throws {}
        func test(_: HermesGatewayID) async throws -> HermesGatewayTestResponse {
            HermesGatewayTestResponse(ok: true, verifiedAt: Date())
        }

        func startPhotonSetup() async throws -> StartPhotonSetupResponse { StartPhotonSetupResponse(sessionID: UUID()) }
        func photonSetupPhone(sessionID: UUID, phone: String) async throws {}
        func photonSetupStream(_ sessionID: UUID) -> AsyncThrowingStream<HermesPhotonSetupEvent, any Error> {
            AsyncThrowingStream { _ in }
        }
    }

    private static func stubEntry(
        id: HermesGatewayID,
        displayName: String,
        description: String,
        status: HermesGatewayStatus,
        verified: Bool = false,
    ) -> HermesGatewayCatalogEntry {
        HermesGatewayCatalogEntry(
            id: id,
            displayName: displayName,
            iconSlug: id.rawValue,
            description: description,
            requiredFields: [
                HermesGatewayField(key: "bot_token", label: "Bot token", placeholder: "abc", kind: .secret, isRequired: true),
            ],
            status: status,
            hasConfig: status != .notConfigured,
            verifiedAt: verified ? Date(timeIntervalSince1970: 1_700_000_000) : nil,
            lastFailureCode: nil,
        )
    }

    private func makeView(_ items: [HermesGatewayCatalogEntry]) -> some View {
        let client = StubHermesGatewaysClient(
            listResult: .success(HermesGatewaysListResponse(items: items)),
        )
        let vm = HermesGatewaysPaneViewModel(client: client)
        vm.state = .loaded(items: items)
        return NavigationStack {
            HermesGatewaysPaneView(client: client)
        }
        .transaction { $0.disablesAnimations = true }
    }

    private var allNotConfigured: [HermesGatewayCatalogEntry] {
        [
            Self.stubEntry(id: .telegram, displayName: "Telegram", description: "Chat with Lumina from Telegram.", status: .notConfigured),
            Self.stubEntry(id: .discord, displayName: "Discord", description: "Connect Lumina to a Discord server.", status: .notConfigured),
            Self.stubEntry(id: .slack, displayName: "Slack", description: "Pipe Lumina into a Slack workspace.", status: .notConfigured),
            Self.stubEntry(id: .whatsapp, displayName: "WhatsApp", description: "Reach Lumina from WhatsApp.", status: .notConfigured),
        ]
    }

    private var mixedConnected: [HermesGatewayCatalogEntry] {
        [
            Self.stubEntry(id: .telegram, displayName: "Telegram", description: "Chat with Lumina from Telegram.", status: .verified, verified: true),
            Self.stubEntry(id: .discord, displayName: "Discord", description: "Connect Lumina to a Discord server.", status: .configured),
            Self.stubEntry(id: .slack, displayName: "Slack", description: "Pipe Lumina into a Slack workspace.", status: .notConfigured),
            Self.stubEntry(id: .whatsapp, displayName: "WhatsApp", description: "Reach Lumina from WhatsApp.", status: .notConfigured),
        ]
    }

    private var errorRow: [HermesGatewayCatalogEntry] {
        [
            Self.stubEntry(id: .telegram, displayName: "Telegram", description: "Chat with Lumina from Telegram.", status: .error),
            Self.stubEntry(id: .discord, displayName: "Discord", description: "Connect Lumina to a Discord server.", status: .notConfigured),
            Self.stubEntry(id: .slack, displayName: "Slack", description: "Pipe Lumina into a Slack workspace.", status: .notConfigured),
            Self.stubEntry(id: .whatsapp, displayName: "WhatsApp", description: "Reach Lumina from WhatsApp.", status: .notConfigured),
        ]
    }

    // MARK: - Cases

    func testAllNotConfiguredDark() {
        snap(makeView(allNotConfigured), scheme: .dark, named: "iPhone13Pro-not-configured-dark")
    }

    func testAllNotConfiguredLight() {
        snap(makeView(allNotConfigured), scheme: .light, named: "iPhone13Pro-not-configured-light")
    }

    func testMixedConnectedDark() {
        snap(makeView(mixedConnected), scheme: .dark, named: "iPhone13Pro-mixed-dark")
    }

    func testMixedConnectedLight() {
        snap(makeView(mixedConnected), scheme: .light, named: "iPhone13Pro-mixed-light")
    }

    func testErrorRowDark() {
        snap(makeView(errorRow), scheme: .dark, named: "iPhone13Pro-error-dark")
    }

    func testErrorRowLight() {
        snap(makeView(errorRow), scheme: .light, named: "iPhone13Pro-error-light")
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
