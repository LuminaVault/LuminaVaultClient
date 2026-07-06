// LuminaVaultClient/LuminaVaultClientTests/TailscaleServerTests.swift
//
// Covers the Tailscale backend-mode wiring: tailnet URL persistence,
// `.tailscale` base-URL resolution, tunnel-aware transport warnings, and the
// picker's test-and-save flow against a mocked health probe. Mirrors
// BYOServerTests — the two modes share the store/editor/probe shape.

import XCTest
import Foundation
import LuminaVaultShared
@testable import LuminaVaultClient

final class TailscaleServerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TailscaleServerStore.set(nil)
        UserDefaults.standard.removeObject(forKey: BackendModeStore.userDefaultsKey)
    }

    override func tearDown() {
        TailscaleServerStore.set(nil)
        UserDefaults.standard.removeObject(forKey: BackendModeStore.userDefaultsKey)
        super.tearDown()
    }

    // MARK: - TailscaleServerStore

    func testStoreRoundTrip() {
        TailscaleServerStore.set("http://hermes-vps.tail562587.ts.net:8080")
        XCTAssertEqual(
            TailscaleServerStore.url?.absoluteString,
            "http://hermes-vps.tail562587.ts.net:8080"
        )
    }

    func testStoreEmptyStringIsNil() {
        TailscaleServerStore.set("")
        XCTAssertNil(TailscaleServerStore.url)
    }

    func testStoreClearIsNil() {
        TailscaleServerStore.set("http://vault.tailnet.ts.net:8080")
        TailscaleServerStore.set(nil)
        XCTAssertNil(TailscaleServerStore.url)
    }

    // MARK: - .tailscale base-URL resolution

    func testTailscaleResolvesToStoredURL() {
        TailscaleServerStore.set("http://100.102.137.69:8080")
        XCTAssertEqual(
            BackendMode.tailscale.defaultBaseURL.absoluteString,
            "http://100.102.137.69:8080"
        )
    }

    func testTailscaleFallsBackToHostedWhenUnset() {
        TailscaleServerStore.set(nil)
        XCTAssertEqual(BackendMode.tailscale.defaultBaseURL, Config.hostedAPIBaseURL)
    }

    func testConfigApiBaseURLFollowsTailscale() {
        TailscaleServerStore.set("http://vault.tail562587.ts.net:8080")
        BackendModeStore.set(.tailscale)
        XCTAssertEqual(Config.apiBaseURL.absoluteString, "http://vault.tail562587.ts.net:8080")
    }

    // MARK: - Tunnel-aware transport warnings

    func testNoWarningForTsNetHostInTunnelMode() {
        XCTAssertNil(URLValidation.transportWarning(
            for: "http://hermes-vps.tail562587.ts.net:8642",
            assumeSecureTunnel: true
        ))
    }

    func testNoWarningForTailscaleIPInTunnelMode() {
        XCTAssertNil(URLValidation.transportWarning(
            for: "http://100.102.137.69:8080",
            assumeSecureTunnel: true
        ))
    }

    func testNoWarningForMagicDNSShortNameInTunnelMode() {
        XCTAssertNil(URLValidation.transportWarning(
            for: "http://hermes-vps:8642",
            assumeSecureTunnel: true
        ))
    }

    func testSoftWarningForPublicHostInTunnelMode() {
        // A public URL pasted into the Tailscale editor must not be silently
        // waved through — it isn't protected by the tunnel.
        XCTAssertNotNil(URLValidation.transportWarning(
            for: "http://vault.example.com",
            assumeSecureTunnel: true
        ))
    }

    func testSoftWarningForNonTailscaleIPInTunnelMode() {
        XCTAssertNotNil(URLValidation.transportWarning(
            for: "http://192.168.1.50:8080",
            assumeSecureTunnel: true
        ))
    }

    func testHTTPWarningStillFiresWithoutTunnelAssumption() {
        XCTAssertNotNil(URLValidation.transportWarning(
            for: "http://hermes-vps.tail562587.ts.net:8642",
            assumeSecureTunnel: false
        ))
    }

    func testIsTailnetHostClassification() {
        XCTAssertTrue(URLValidation.isTailnetHost("hermes-vps.tail562587.ts.net"))
        XCTAssertTrue(URLValidation.isTailnetHost("100.64.0.1"))
        XCTAssertTrue(URLValidation.isTailnetHost("100.127.255.255"))
        XCTAssertTrue(URLValidation.isTailnetHost("fd7a:115c:a1e0::6f01:89b5"))
        XCTAssertTrue(URLValidation.isTailnetHost("hermes-vps"))
        XCTAssertFalse(URLValidation.isTailnetHost("100.63.0.1"))
        XCTAssertFalse(URLValidation.isTailnetHost("100.128.0.1"))
        XCTAssertFalse(URLValidation.isTailnetHost("192.168.1.50"))
        XCTAssertFalse(URLValidation.isTailnetHost("vault.example.com"))
    }

    // MARK: - testAndSaveTailscale flow

    @MainActor
    func testTestAndSavePersistsAndSwitchesWhenReachable() async {
        let health = MockHealthClient()
        health.online = true
        let vm = ServerConnectionViewModel(soulClient: StubSoulClient(), healthClient: health)
        vm.tailscaleURLInput = "http://hermes-vps.tail562587.ts.net:8080"

        await vm.testAndSaveTailscale()

        XCTAssertNil(vm.tailscaleError)
        XCTAssertEqual(
            TailscaleServerStore.url?.absoluteString,
            "http://hermes-vps.tail562587.ts.net:8080"
        )
        XCTAssertEqual(BackendModeStore.current, .tailscale)
        XCTAssertEqual(
            health.lastProbedBaseURL?.absoluteString,
            "http://hermes-vps.tail562587.ts.net:8080"
        )
    }

    @MainActor
    func testTestAndSaveDoesNotPersistWhenUnreachable() async {
        let health = MockHealthClient()
        health.online = false
        let vm = ServerConnectionViewModel(soulClient: StubSoulClient(), healthClient: health)
        vm.tailscaleURLInput = "http://unreachable.tail562587.ts.net:8080"

        await vm.testAndSaveTailscale()

        XCTAssertNotNil(vm.tailscaleError)
        XCTAssertNil(TailscaleServerStore.url)
    }

    @MainActor
    func testTestAndSaveRejectsInvalidURL() async {
        let health = MockHealthClient()
        let vm = ServerConnectionViewModel(soulClient: StubSoulClient(), healthClient: health)
        vm.tailscaleURLInput = "not a url"

        await vm.testAndSaveTailscale()

        XCTAssertNotNil(vm.tailscaleError)
        XCTAssertNil(TailscaleServerStore.url)
        XCTAssertEqual(health.callCount, 0)
    }
}

private struct StubSoulClient: SoulClientProtocol {
    func get() async throws -> SoulResponse { SoulResponse(markdown: "", updatedAt: nil) }
    func put(_ body: SoulPutRequest) async throws -> SoulResponse {
        SoulResponse(markdown: body.markdown, updatedAt: nil)
    }
    func compose(_ body: SoulComposeRequest) async throws -> SoulResponse {
        SoulResponse(markdown: "", updatedAt: nil)
    }
    func delete() async throws {}
}
