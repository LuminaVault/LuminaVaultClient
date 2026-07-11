// LuminaVaultClient/LuminaVaultClientTests/AuthLandingViewTests.swift
// HER-140 — unit tests for the AuthProviderOption enum + preferred-method
// persistence helpers. The view layer itself is exercised by the SwiftUI
// preview + manual test plan; here we lock the wire-format of the
// preferred-provider UserDefaults key.
import XCTest
@testable import LuminaVaultClient

final class AuthLandingViewTests: XCTestCase {
    private let preferenceKey = "lv.auth.preferredProvider"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: preferenceKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: preferenceKey)
        super.tearDown()
    }

    func testProviderOptionRawValuesAreStable() {
        // Persisted in UserDefaults — changing these strings invalidates
        // every existing install's "last used" emphasis.
        XCTAssertEqual(AuthProviderOption.apple.rawValue, "apple")
        XCTAssertEqual(AuthProviderOption.google.rawValue, "google")
        XCTAssertEqual(AuthProviderOption.x.rawValue, "x")
        XCTAssertEqual(AuthProviderOption.phone.rawValue, "phone")
        XCTAssertEqual(AuthProviderOption.email.rawValue, "email")
    }

    func testProviderOptionMapsToSSOProviderOnlyForOAuthCases() {
        XCTAssertEqual(AuthProviderOption.apple.ssoProvider, .apple)
        XCTAssertEqual(AuthProviderOption.google.ssoProvider, .google)
        XCTAssertEqual(AuthProviderOption.x.ssoProvider, .x)
        XCTAssertNil(AuthProviderOption.phone.ssoProvider)
        XCTAssertNil(AuthProviderOption.email.ssoProvider)
    }

    func testPreferredProviderRoundTripsThroughUserDefaults() {
        // Mirror the @AppStorage binding inside AuthLandingView: a write
        // to the same key must surface as a parsed AuthProviderOption.
        UserDefaults.standard.set("phone", forKey: preferenceKey)
        let raw = UserDefaults.standard.string(forKey: preferenceKey) ?? ""
        XCTAssertEqual(AuthProviderOption(rawValue: raw), .phone)
    }

    func testUnknownPreferredProviderResolvesToNil() {
        UserDefaults.standard.set("totally-not-a-provider", forKey: preferenceKey)
        let raw = UserDefaults.standard.string(forKey: preferenceKey) ?? ""
        XCTAssertNil(AuthProviderOption(rawValue: raw))
    }

    func testAllCasesAreSurfacedByCaseIterable() {
        // Lock the ordering — UI relies on `AuthProviderOption.allCases`
        // staying in this order for snapshot tests when they land.
        XCTAssertEqual(
            AuthProviderOption.allCases,
            [.apple, .google, .x, .passkey, .phone, .email]
        )
    }
}
