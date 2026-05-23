// LuminaVaultClient/LuminaVaultClientTests/AboutPaneSmokeTests.swift
//
// HER-298 — smoke coverage for the Config additions surfaced by the
// About pane. Asserts every URL parses with a non-nil host, the version
// string is well-formed, and the support email looks like an email.
// Does NOT pin specific values (those will be overridden via Info.plist
// per environment) — just that nothing silently breaks.

import XCTest
@testable import LuminaVaultClient

final class AboutPaneSmokeTests: XCTestCase {

    // MARK: - Social URLs

    func testTikTokURLHasHost() {
        XCTAssertNotNil(Config.tiktokURL.host)
        XCTAssertEqual(Config.tiktokURL.scheme, "https")
    }

    func testXProfileURLHasHost() {
        XCTAssertNotNil(Config.xProfileURL.host)
        XCTAssertEqual(Config.xProfileURL.scheme, "https")
    }

    func testInstagramURLHasHost() {
        XCTAssertNotNil(Config.instagramURL.host)
        XCTAssertEqual(Config.instagramURL.scheme, "https")
    }

    // MARK: - Brand / contact

    func testWebsiteURLHasHost() {
        XCTAssertNotNil(Config.websiteURL.host)
        XCTAssertEqual(Config.websiteURL.scheme, "https")
    }

    func testSupportEmailLooksLikeAnEmail() {
        let email = Config.supportEmail
        XCTAssertTrue(email.contains("@"), "support email must contain @")
        XCTAssertTrue(email.contains("."), "support email must contain a domain dot")
        XCTAssertFalse(email.isEmpty)
    }

    func testSupportEmailMakesValidMailtoURL() {
        let mailto = URL(string: "mailto:\(Config.supportEmail)")
        XCTAssertNotNil(mailto)
    }

    // MARK: - Version

    func testAppVersionStringStartsWithVAndContainsBuild() {
        let v = Config.appVersionString
        XCTAssertTrue(v.hasPrefix("v"), "version string must start with 'v', got: \(v)")
        XCTAssertTrue(v.contains("build"), "version string must contain 'build': \(v)")
    }
}
