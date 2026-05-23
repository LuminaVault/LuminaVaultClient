// LuminaVaultClient/LuminaVaultClientTests/GatewaysSetupViewSnapshotTests.swift
//
// HER-241 — image snapshots for the onboarding GatewaysSetupView.
// 3 cases × 2 schemes = 6 baselines.

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient
@testable import LuminaVaultShared

@MainActor
final class GatewaysSetupViewSnapshotTests: XCTestCase {
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
    }

    private static func entry(_ id: HermesGatewayID, status: HermesGatewayStatus) -> HermesGatewayCatalogEntry {
        let descs: [HermesGatewayID: (String, String)] = [
            .telegram: ("Telegram", "Chat with Lumina from Telegram."),
            .discord: ("Discord", "Connect Lumina to a Discord server."),
            .slack: ("Slack", "Pipe Lumina into a Slack workspace."),
            .whatsapp: ("WhatsApp", "Reach Lumina from WhatsApp."),
        ]
        let (displayName, desc) = descs[id]!
        return HermesGatewayCatalogEntry(
            id: id,
            displayName: displayName,
            iconSlug: id.rawValue,
            description: desc,
            requiredFields: [],
            status: status,
            hasConfig: status != .notConfigured,
            verifiedAt: nil,
            lastFailureCode: nil,
        )
    }

    private func makeView(items: [HermesGatewayCatalogEntry]) -> some View {
        let client = StubHermesGatewaysClient(
            listResult: .success(HermesGatewaysListResponse(items: items)),
        )
        let vm = GatewaysSetupViewModel(
            telemetry: NoopTelemetry(),
            client: client,
            onContinue: {},
            onSkip: {},
        )
        vm.state = .loaded(items: items)
        return NavigationStack {
            GatewaysSetupView(viewModel: vm, client: client)
        }
        .transaction { $0.disablesAnimations = true }
    }

    private var initialItems: [HermesGatewayCatalogEntry] {
        [.telegram, .discord, .slack, .whatsapp].map { Self.entry($0, status: .notConfigured) }
    }

    private var oneConnected: [HermesGatewayCatalogEntry] {
        [
            Self.entry(.telegram, status: .verified),
            Self.entry(.discord, status: .notConfigured),
            Self.entry(.slack, status: .notConfigured),
            Self.entry(.whatsapp, status: .notConfigured),
        ]
    }

    private var allConnected: [HermesGatewayCatalogEntry] {
        [.telegram, .discord, .slack, .whatsapp].map { Self.entry($0, status: .verified) }
    }

    // MARK: - Cases

    func testInitialDark() {
        snap(makeView(items: initialItems), scheme: .dark, named: "iPhone13Pro-initial-dark")
    }

    func testInitialLight() {
        snap(makeView(items: initialItems), scheme: .light, named: "iPhone13Pro-initial-light")
    }

    func testOneConnectedDark() {
        snap(makeView(items: oneConnected), scheme: .dark, named: "iPhone13Pro-one-connected-dark")
    }

    func testOneConnectedLight() {
        snap(makeView(items: oneConnected), scheme: .light, named: "iPhone13Pro-one-connected-light")
    }

    func testAllConnectedDark() {
        snap(makeView(items: allConnected), scheme: .dark, named: "iPhone13Pro-all-connected-dark")
    }

    func testAllConnectedLight() {
        snap(makeView(items: allConnected), scheme: .light, named: "iPhone13Pro-all-connected-light")
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
