// LuminaVaultClient/LuminaVaultClientTests/BYOServerTests.swift
//
// Covers the BYO (self-hosted) LuminaVault server wiring: URL persistence,
// `.byo` base-URL resolution, URL validation, and the picker's test-and-save
// flow against a mocked health probe.

import XCTest
import Foundation
import LuminaVaultShared
@testable import LuminaVaultClient

final class BYOServerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        BYOServerStore.set(nil)
        UserDefaults.standard.removeObject(forKey: BackendModeStore.userDefaultsKey)
    }

    override func tearDown() {
        BYOServerStore.set(nil)
        UserDefaults.standard.removeObject(forKey: BackendModeStore.userDefaultsKey)
        super.tearDown()
    }

    // MARK: - BYOServerStore

    func testStoreRoundTrip() {
        BYOServerStore.set("https://vault.example.com")
        XCTAssertEqual(BYOServerStore.url?.absoluteString, "https://vault.example.com")
    }

    func testStoreEmptyStringIsNil() {
        BYOServerStore.set("")
        XCTAssertNil(BYOServerStore.url)
    }

    func testStoreClearIsNil() {
        BYOServerStore.set("https://vault.example.com")
        BYOServerStore.set(nil)
        XCTAssertNil(BYOServerStore.url)
    }

    // MARK: - .byo base-URL resolution

    func testByoResolvesToStoredURL() {
        BYOServerStore.set("https://my.host:8443")
        XCTAssertEqual(BackendMode.byo.defaultBaseURL.absoluteString, "https://my.host:8443")
    }

    func testByoFallsBackToHostedWhenUnset() {
        BYOServerStore.set(nil)
        XCTAssertEqual(BackendMode.byo.defaultBaseURL, Config.hostedAPIBaseURL)
    }

    func testConfigApiBaseURLFollowsByo() {
        BYOServerStore.set("https://my.host:8443")
        BackendModeStore.set(.byo)
        XCTAssertEqual(Config.apiBaseURL.absoluteString, "https://my.host:8443")
    }

    // MARK: - URL validation

    func testValidationAcceptsHttps() {
        XCTAssertTrue(URLValidation.isValidBaseURL("https://vault.example.com"))
    }

    func testValidationRejectsSchemeless() {
        XCTAssertFalse(URLValidation.isValidBaseURL("vault.example.com"))
    }

    func testValidationRejectsNonHTTP() {
        XCTAssertFalse(URLValidation.isValidBaseURL("ftp://vault.example.com"))
    }

    func testTransportWarningForHTTP() {
        XCTAssertNotNil(URLValidation.transportWarning(for: "http://vault.example.com"))
    }

    func testTransportWarningForBareIP() {
        XCTAssertNotNil(URLValidation.transportWarning(for: "https://192.168.1.50:8080"))
    }

    func testNoTransportWarningForHTTPSDomain() {
        XCTAssertNil(URLValidation.transportWarning(for: "https://vault.example.com"))
    }

    // MARK: - testAndSave flow

    @MainActor
    func testTestAndSavePersistsAndSwitchesWhenReachable() async {
        let health = MockHealthClient()
        health.online = true
        let vm = ServerConnectionViewModel(soulClient: StubSoulClient(), healthClient: health)
        vm.byoURLInput = "https://reachable.example.com"

        await vm.testAndSave()

        XCTAssertNil(vm.byoError)
        XCTAssertEqual(BYOServerStore.url?.absoluteString, "https://reachable.example.com")
        XCTAssertEqual(BackendModeStore.current, .byo)
        XCTAssertEqual(health.lastProbedBaseURL?.absoluteString, "https://reachable.example.com")
    }

    @MainActor
    func testTestAndSaveDoesNotPersistWhenUnreachable() async {
        let health = MockHealthClient()
        health.online = false
        let vm = ServerConnectionViewModel(soulClient: StubSoulClient(), healthClient: health)
        vm.byoURLInput = "https://down.example.com"

        await vm.testAndSave()

        XCTAssertNotNil(vm.byoError)
        XCTAssertNil(BYOServerStore.url)
    }

    @MainActor
    func testTestAndSaveRejectsInvalidURL() async {
        let health = MockHealthClient()
        let vm = ServerConnectionViewModel(soulClient: StubSoulClient(), healthClient: health)
        vm.byoURLInput = "not a url"

        await vm.testAndSave()

        XCTAssertNotNil(vm.byoError)
        XCTAssertNil(BYOServerStore.url)
        XCTAssertEqual(health.callCount, 0)
    }
}

private struct StubSoulClient: SoulClientProtocol {
    func get() async throws -> SoulResponse { SoulResponse(markdown: "", updatedAt: nil) }
    func put(_ body: SoulPutRequest) async throws -> SoulResponse {
        SoulResponse(markdown: body.markdown, updatedAt: nil)
    }
    func delete() async throws {}
}
