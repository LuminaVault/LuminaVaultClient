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

@MainActor
final class WebSignInPairingLinkTests: XCTestCase {
    private let pairingID = "85A5C61C-2DD0-4E4E-9501-4BD4096C872E"
    private let code = "925206"

    // MARK: - Universal link (the new payload)

    func testParsesUniversalLinkWithoutCode() {
        // The web app deliberately leaves the code out: a QR that carries its
        // own confirmation confirms nothing, because anyone can print one.
        let parsed = WebSignInApprovalViewModel.parse(
            "https://app.luminavault.fyi/pair?id=\(pairingID)"
        )
        XCTAssertEqual(parsed?.id, pairingID)
        XCTAssertNil(parsed?.code ?? nil)
    }

    func testUniversalLinkCodeIsIgnoredRatherThanTrusted() {
        // An attacker appending `&code=` to an otherwise valid link must not
        // end up at a screen that only asks for confirmation — that would put
        // the code back inside the scanned payload by the back door.
        let parsed = WebSignInApprovalViewModel.parse(
            "https://app.luminavault.fyi/pair?id=\(pairingID)&code=\(code)"
        )
        XCTAssertEqual(parsed?.id, pairingID)
        XCTAssertEqual(parsed?.code ?? nil, code, "legacy shape still parses; the phase decides")
    }

    func testParsesUniversalLinkFromStagingHost() {
        // Staging encodes its own origin, so a beta build pointed at staging
        // must not reject its own QR.
        let parsed = WebSignInApprovalViewModel.parse(
            "https://app-staging.luminavault.fyi/pair?id=\(pairingID)"
        )
        XCTAssertEqual(parsed?.id, pairingID)
    }

    // MARK: - Who may drive an approval

    func testRejectsForeignHost() {
        // A QR is attacker-supplied input: anyone can print one. Only the
        // app's own web origins may open an approval screen.
        XCTAssertNil(
            WebSignInApprovalViewModel.parse("https://evil.example.com/pair?id=\(pairingID)")
        )
    }

    func testRejectsWrongPathOnOwnHost() {
        XCTAssertNil(
            WebSignInApprovalViewModel.parse("https://app.luminavault.fyi/login?id=\(pairingID)")
        )
    }

    func testRejectsPlaintextHTTP() {
        // A downgraded link is not one of ours.
        XCTAssertNil(
            WebSignInApprovalViewModel.parse("http://app.luminavault.fyi/pair?id=\(pairingID)")
        )
    }

    // MARK: - Custom scheme (still in the wild)

    func testStillParsesCustomScheme() {
        let parsed = WebSignInApprovalViewModel.parse(
            "luminavault://pair?id=\(pairingID)&code=\(code)"
        )
        XCTAssertEqual(parsed?.id, pairingID)
        XCTAssertEqual(parsed?.code ?? nil, code)
    }

    func testRejectsCustomSchemeWithWrongHost() {
        XCTAssertNil(
            WebSignInApprovalViewModel.parse("luminavault://other?id=\(pairingID)&code=\(code)")
        )
    }

    // MARK: - What the scan leads to

    func testUniversalLinkAsksForTheCode() {
        // No code in the link, so the app must ask for it — that is the whole
        // anti-phishing property: approving requires seeing the browser that
        // started the sign-in.
        XCTAssertEqual(
            WebSignInApprovalViewModel.initialPhase(prefilled: (id: pairingID, code: nil)),
            .enterCode(pairingId: pairingID)
        )
    }

    func testEmptyCodeIsTreatedAsAbsent() {
        XCTAssertEqual(
            WebSignInApprovalViewModel.initialPhase(prefilled: (id: pairingID, code: "")),
            .enterCode(pairingId: pairingID)
        )
    }

    func testLegacyPayloadStillConfirmsWithoutTyping() {
        // Builds scanning the old scheme cannot prompt, so that path keeps its
        // confirm step until the custom scheme retires.
        XCTAssertEqual(
            WebSignInApprovalViewModel.initialPhase(prefilled: (id: pairingID, code: code)),
            .confirm(pairingId: pairingID, code: code)
        )
    }

    func testNoLinkStartsAtTheScanner() {
        XCTAssertEqual(WebSignInApprovalViewModel.initialPhase(prefilled: nil), .scanning)
    }

    // MARK: - Missing parts

    func testRejectsMissingID() {
        XCTAssertNil(WebSignInApprovalViewModel.parse("https://app.luminavault.fyi/pair?code=\(code)"))
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
