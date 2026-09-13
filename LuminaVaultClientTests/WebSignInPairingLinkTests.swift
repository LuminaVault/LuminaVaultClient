// LuminaVaultClient/LuminaVaultClientTests/WebSignInPairingLinkTests.swift
//
// The QR payload is a cross-repo contract with LuminaVaultWebApp, and getting
// it wrong is invisible from either side: the code renders, the scanner opens,
// nothing matches.
//
// The payload moved from `luminavault://pair?…` to a universal link on
// app.luminavault.fyi, because no installed app claims that custom scheme —
// Info.plist registers only the Google reversed client id and the X redirect
// scheme — so the iPhone camera answered "No usable data found". Both forms
// must parse: the web switch flips only after a build carrying this ships, and
// a QR generated before that switch has to keep working afterwards.

import XCTest
@testable import LuminaVaultClient

final class WebSignInPairingLinkTests: XCTestCase {
    private let pairingID = "85A5C61C-2DD0-4E4E-9501-4BD4096C872E"
    private let code = "925206"

    // MARK: - Universal link (the new payload)

    func testParsesUniversalLink() {
        let parsed = WebSignInApprovalViewModel.parse(
            "https://app.luminavault.fyi/pair?id=\(pairingID)&code=\(code)"
        )
        XCTAssertEqual(parsed?.id, pairingID)
        XCTAssertEqual(parsed?.code, code)
    }

    func testParsesUniversalLinkFromStagingHost() {
        // Staging encodes its own origin, so a beta build pointed at staging
        // must not reject its own QR.
        let parsed = WebSignInApprovalViewModel.parse(
            "https://app-staging.luminavault.fyi/pair?id=\(pairingID)&code=\(code)"
        )
        XCTAssertEqual(parsed?.id, pairingID)
    }

    func testRejectsForeignHost() {
        // An attacker-controlled page can put any URL in a QR. Only the app's
        // own domains may drive an approval screen.
        XCTAssertNil(
            WebSignInApprovalViewModel.parse(
                "https://evil.example.com/pair?id=\(pairingID)&code=\(code)"
            )
        )
    }

    func testRejectsWrongPathOnOwnHost() {
        XCTAssertNil(
            WebSignInApprovalViewModel.parse(
                "https://app.luminavault.fyi/login?id=\(pairingID)&code=\(code)"
            )
        )
    }

    func testRejectsPlaintextHTTP() {
        XCTAssertNil(
            WebSignInApprovalViewModel.parse(
                "http://app.luminavault.fyi/pair?id=\(pairingID)&code=\(code)"
            )
        )
    }

    // MARK: - Custom scheme (still in the wild)

    func testStillParsesCustomScheme() {
        let parsed = WebSignInApprovalViewModel.parse(
            "luminavault://pair?id=\(pairingID)&code=\(code)"
        )
        XCTAssertEqual(parsed?.id, pairingID)
        XCTAssertEqual(parsed?.code, code)
    }

    func testRejectsCustomSchemeWithWrongHost() {
        XCTAssertNil(
            WebSignInApprovalViewModel.parse("luminavault://other?id=\(pairingID)&code=\(code)")
        )
    }

    // MARK: - Missing parts

    func testRejectsMissingCode() {
        XCTAssertNil(
            WebSignInApprovalViewModel.parse("https://app.luminavault.fyi/pair?id=\(pairingID)")
        )
    }

    func testRejectsEmptyID() {
        XCTAssertNil(
            WebSignInApprovalViewModel.parse("https://app.luminavault.fyi/pair?id=&code=\(code)")
        )
    }

    func testRejectsArbitraryText() {
        XCTAssertNil(WebSignInApprovalViewModel.parse("just some text"))
    }
}
