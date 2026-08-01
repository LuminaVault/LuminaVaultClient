// LuminaVaultClient/LuminaVaultClientTests/CertificatePinningTests.swift
//
// The TLS pin set had ZERO test coverage, and that is precisely why a Let's
// Encrypt CA rotation (YE1/Root X2 → YR2/Root YR) shipped to production and
// cancelled every API call: chat never replied, the inbox read "No chats yet",
// and the Brain tab span forever, with no error anywhere. `BaseHTTPClientTests`
// injects `URLSession.shared`, so it never exercised the pinning path at all.
//
// These tests pin the pins. `testPinnedHashesMatchTheRealCAs` is the tripwire:
// it recomputes the SPKI digests from real embedded CA certificates and fails
// the moment `pinnedSPKISHA256` drifts away from them.

@testable import LuminaVaultClient
import XCTest

final class CertificatePinningTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PinningFailureLog.reset()
    }

    override func tearDown() {
        PinningFailureLog.reset()
        super.tearDown()
    }

    // MARK: - Fixtures

    private enum Fixtures {
        /// Let's Encrypt YR2 intermediate (RSA-2048)
        static let leYR2 = """
            MIIE2jCCAsKgAwIBAgIQTr0klH4k05SALYSlL9WzGTANBgkqhkiG9w0BAQsFADAuMQswCQYDVQQG
            EwJVUzENMAsGA1UEChMESVNSRzEQMA4GA1UEAxMHUm9vdCBZUjAeFw0yNTA5MDMwMDAwMDBaFw0y
            ODA5MDIyMzU5NTlaMDMxCzAJBgNVBAYTAlVTMRYwFAYDVQQKEw1MZXQncyBFbmNyeXB0MQwwCgYD
            VQQDEwNZUjIwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDZ0LxwBppqh84luqMerV/e
            eL/fXQ7mLQQv1LnpWKZbyvGpx6wh6AfnslAnF6ewTkcHA+gSOoBvm3Dfm06AuGiF+KRut4fAcowq
            nAQQCW98+QPP/eOv/wug7Iyk4NkOxf2I6g2f55T6nJoOTLFcukeRq80JGQEYan+dPFr9OGUgQK2h
            GKgNkW87pappsOAuUJcroYhRt5uUis4qaZireiseu32gzDJNBAiKtsvd6HX4v25bpkRNcS/B/Gtc
            9kVbUpD+2PLPxdei3Tim55k4tfAEXwD2qyiPTxrTNq6lN+AMr5g2c1dNqkOTwjxeV6L5lpP1rGiY
            vLnRaPlOqyZRPW+5AgMBAAGjge4wgeswDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUF
            BwMBMBIGA1UdEwEB/wQIMAYBAf8CAQAwHQYDVR0OBBYEFEAVLSZ57TIgnt+ach3WMh+BDIEMMB8G
            A1UdIwQYMBaAFN7nW2DQIm1AKH0/DQH+pLVStFGUMDIGCCsGAQUFBwEBBCYwJDAiBggrBgEFBQcw
            AoYWaHR0cDovL3lyLmkubGVuY3Iub3JnLzATBgNVHSAEDDAKMAgGBmeBDAECATAnBgNVHR8EIDAe
            MBygGqAYhhZodHRwOi8veXIuYy5sZW5jci5vcmcvMA0GCSqGSIb3DQEBCwUAA4ICAQB0ZUQWZ9/Y
            n9COEpo+JfecMnB0h0vwDm/M66IqXqw3LoaLmx9lZvRTeDIS67PUeI3yCA2W6PKRD0/FE/G57lOm
            S+Xy5AaaL00ICGOqjNcCaMWW8o8nevHOd4i4lqgtznE/28QwlcdJyF8yBiWHpnyjhEpmNWJURgOC
            Og2xpwRMBCsjMScqYPtOhBeuYQvSwAEeTML2Ukh6uGuX4E14q65Ja8cdjF5bAldnP1eE4FBaAwsZ
            G2fOqqrKV03Y85Nw2btedP1AtliQuJZs/Jo/gXxXdc7LrH3McgnpnbTiAncX7yEShP6kzQejllqM
            CIt52HOjxDGWafS7Xw+DKwqmH+Eqy8dcbOuag/1AYlQoKNVK3F5qHh6tEDiMqQcLIibGKteE6iHo
            4A/bIScbzrhXUYuism42ZYzmc48FMVIH3qy4L84ETdAH2gtxw0PAhvRVXp8HP7wfngpzsN/8xOTp
            eRSbM4+Qbc56G6+Bifmv6sk1ieQbNA3wJdl4DDUuQSV8hBgx6zoI1ZSGORprDFux7c6rhc77QZMS
            RrEgomBeklervEve86ylWmZ3WWHV6RLMi8xNvjd71r4EPIGgY7BZU/VPBkq+uA7Gb6mbJnFgV43u
            h3xyLRFgxIAphIukwTGSMZZR+AI+Qnp0BYTWovHXozOf3H8r6hozEoT02JHn0AeTfA==
            """

        /// ISRG Root YR, cross-signed by ISRG Root X1 (RSA-4096)
        static let isrgRootYR = """
            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
            """

        /// ISRG Root X1 (RSA-4096)
        static let isrgRootX1 = """
            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
            m+kXQ99b21/+jh5Xos1AnX5iItreGCc=
            """

        /// ISRG Root X2 — the root this file used to *claim* it pinned. It is not
        /// in the production chain, which makes it the ideal negative fixture.
        static let unrelatedCA = """
            MIICGzCCAaGgAwIBAgIQQdKd0XLq7qeAwSxs6S+HUjAKBggqhkjOPQQDAzBPMQswCQYDVQQGEwJV
            UzEpMCcGA1UEChMgSW50ZXJuZXQgU2VjdXJpdHkgUmVzZWFyY2ggR3JvdXAxFTATBgNVBAMTDElT
            UkcgUm9vdCBYMjAeFw0yMDA5MDQwMDAwMDBaFw00MDA5MTcxNjAwMDBaME8xCzAJBgNVBAYTAlVT
            MSkwJwYDVQQKEyBJbnRlcm5ldCBTZWN1cml0eSBSZXNlYXJjaCBHcm91cDEVMBMGA1UEAxMMSVNS
            RyBSb290IFgyMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAEzZvVn4CDCuwJSvMWSj5cz3es3mcFDR0H
            ttwW+1qLFNvicWDEukWVEYmO6gbf9yoWHKS5xcUy4APgHoIYOIvXRdgKam7mAHf7AlF9ItgKbppb
            d9/w+kHsOdx1ymgHDB/qo0IwQDAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUwAwEB/zAdBgNV
            HQ4EFgQUfEKWrt5LSDv6kviejM9ti6lyN5UwCgYIKoZIzj0EAwMDaAAwZQIwe3lORlCEwkSHRhtF
            cP9Ymd70/aTSVaYgLXTWNLxBo1BfASdWtL4ndQavEi51mI38AjEAi/V3bNTIZargCyzuFJ0nN6T5
            U6VR5CmD1/iQMVtCnwr1/q4AaOeMSQ+2b1tbFfLn
            """
    }

    private func certificate(_ base64: String) throws -> SecCertificate {
        let der = try XCTUnwrap(
            Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
            "fixture is not valid base64",
        )
        return try XCTUnwrap(
            SecCertificateCreateWithData(nil, der as CFData),
            "fixture is not a parseable X.509 certificate",
        )
    }

    // MARK: - SPKI reconstruction

    /// `SecKeyCopyExternalRepresentation` hands back a PKCS#1 `RSAPublicKey`,
    /// not a SubjectPublicKeyInfo. If the ASN.1 header table is wrong, every
    /// digest silently mismatches and the app blocks its own traffic — so
    /// assert the reconstruction against known-good values.
    func testSPKIDigestsMatchTheRealCAs() throws {
        let expected: [(String, String)] = [
            (Fixtures.leYR2, "9d637b3d27a9e570d07607b9ccadb80a70915c7af72afce12841b1b1da825fd1"),
            (Fixtures.isrgRootYR, "7e4e8838a8add6295de7ae3b047d3aba3488ab95db0a0aa56d897a00d8618bcf"),
            (Fixtures.isrgRootX1, "0b9fa5a59eed715c26c1020c711b4f6ec42d58b0015e14337a39dad301c5afc3"),
        ]
        for (base64, digest) in expected {
            let cert = try certificate(base64)
            XCTAssertEqual(CertificatePinningDelegate.spkiSHA256(for: cert), digest)
        }
    }

    /// The shipped pin set must contain exactly the CAs above. This is what
    /// fails when someone edits `pinnedSPKISHA256` without checking the chain.
    func testPinnedHashesMatchTheRealCAs() throws {
        for base64 in [Fixtures.leYR2, Fixtures.isrgRootYR, Fixtures.isrgRootX1] {
            let cert = try certificate(base64)
            let digest = try XCTUnwrap(CertificatePinningDelegate.spkiSHA256(for: cert))
            XCTAssertTrue(
                CertificatePinningDelegate.pinnedSPKISHA256.contains(digest),
                "pin set is missing \(digest) — the chain rotated, or a pin was dropped",
            )
        }
    }

    /// Full-DER hashing is retained as a second accepted form; confirm it still
    /// produces the documented values so a rollback path stays available.
    func testCertificateDERDigests() throws {
        let expected: [(String, String)] = [
            (Fixtures.leYR2, "238b85a0099c65b970477d5724f1a1d475ce5058cffe4efa8733899bdb863c47"),
            (Fixtures.isrgRootYR, "072639d0b140d5bffae16ad9c3f6cc6086040621f51ee61a6d46a8915c07cf76"),
            (Fixtures.isrgRootX1, "96bcec06264976f37460779acf28c5a7cfe8a3c0aae11a8ffcee05c0bddf08c6"),
        ]
        for (base64, digest) in expected {
            let cert = try certificate(base64)
            XCTAssertEqual(CertificatePinningDelegate.certificateSHA256(for: cert), digest)
        }
    }

    /// The legacy pins target the retired YE1/Root X2 hierarchy. They are kept
    /// deliberately, but they must not be what is keeping the app alive — if
    /// the SPKI pins were dropped these would NOT match the live chain.
    func testLegacyDERPinsDoNotMatchTheCurrentChain() throws {
        for base64 in [Fixtures.leYR2, Fixtures.isrgRootYR, Fixtures.isrgRootX1] {
            let cert = try certificate(base64)
            let digest = CertificatePinningDelegate.certificateSHA256(for: cert)
            XCTAssertFalse(CertificatePinningDelegate.pinnedCertSHA256.contains(digest))
        }
    }

    // MARK: - Chain evaluation

    func testChainContainingAPinnedCAIsAccepted() throws {
        let chain = [try certificate(Fixtures.leYR2), try certificate(Fixtures.isrgRootYR)]
        XCTAssertTrue(CertificatePinningDelegate.chainContainsPinnedCA(chain))
    }

    func testChainWithoutAPinnedCAIsRejected() throws {
        // A syntactically valid certificate that is not one of our CAs.
        let stranger = try certificate(Fixtures.unrelatedCA)
        XCTAssertFalse(CertificatePinningDelegate.chainContainsPinnedCA([stranger]))
    }

    func testEmptyChainIsRejected() {
        XCTAssertFalse(CertificatePinningDelegate.chainContainsPinnedCA([]))
    }

    // MARK: - Expiry fail-open

    /// The whole point of `pinsValidUntil`: a build that outlives its pins must
    /// degrade to system trust, never black-hole itself the way the YE1 → YR2
    /// rotation did.
    func testPinsAreNotExpiredToday() {
        XCTAssertFalse(CertificatePinningDelegate.pinsAreExpired())
    }

    func testPinsExpireAfterTheValidUntilDate() {
        let after = CertificatePinningDelegate.pinsValidUntil.addingTimeInterval(1)
        XCTAssertTrue(CertificatePinningDelegate.pinsAreExpired(now: after))
    }

    /// The expiry has to outlive plausible review + adoption time, or shipping
    /// it is pointless. Guard against someone setting a date in the past.
    func testExpiryIsComfortablyInTheFuture() {
        XCTAssertGreaterThan(
            CertificatePinningDelegate.pinsValidUntil.timeIntervalSinceNow,
            60 * 60 * 24 * 90,
            "pinsValidUntil is under 90 days out — rotate the pins before shipping",
        )
    }

    // MARK: - Failure log + error classification

    func testPinFailureIsNotClassifiedAsBenignCancellation() {
        PinningFailureLog.record(host: "api.luminavault.fyi", presentedChain: ["Evil CA"])

        let cancelled = URLError(.cancelled)
        XCTAssertTrue(APIError.isTLSPinningFailure(cancelled))
        XCTAssertFalse(APIError.isBenignCancellation(cancelled))
        XCTAssertFalse(APIError.isBenignCancellation(APIError.networkFailure(cancelled)))
    }

    func testTLSPinningFailedCaseIsNeverBenign() {
        XCTAssertFalse(APIError.isBenignCancellation(APIError.tlsPinningFailed(host: "h")))
    }

    func testTransportPromotesAPinFailureOutOfNetworkFailure() {
        PinningFailureLog.record(host: "api.luminavault.fyi", presentedChain: [])
        guard case .tlsPinningFailed = APIError.transport(URLError(.cancelled)) else {
            return XCTFail("expected a pin failure to be promoted to .tlsPinningFailed")
        }
    }

    func testTransportLeavesOrdinaryFailuresAlone() {
        guard case .networkFailure = APIError.transport(URLError(.timedOut)) else {
            return XCTFail("a timeout is not a pinning failure")
        }
    }

    /// Without a recorded rejection a cancel is still an ordinary cancel —
    /// otherwise every SwiftUI `.task` teardown would surface as an error.
    func testCancellationStaysBenignWithoutARecordedPinFailure() {
        XCTAssertTrue(APIError.isBenignCancellation(URLError(.cancelled)))
        XCTAssertTrue(APIError.isBenignCancellation(CancellationError()))
    }

    func testFailureCorrelationExpiresWithTheWindow() {
        let stale = Date().addingTimeInterval(-(PinningFailureLog.correlationWindow + 1))
        PinningFailureLog.record(host: "api.luminavault.fyi", presentedChain: [], at: stale)

        XCTAssertNil(PinningFailureLog.recentFailure(for: "api.luminavault.fyi"))
        XCTAssertFalse(PinningFailureLog.hasRecentFailure())
        XCTAssertTrue(APIError.isBenignCancellation(URLError(.cancelled)))
    }

    func testFailureLookupIsCaseInsensitive() {
        PinningFailureLog.record(host: "API.LuminaVault.FYI", presentedChain: [])
        XCTAssertNotNil(PinningFailureLog.recentFailure(for: "api.luminavault.fyi"))
    }

    func testTLSPinningFailedHasAUserFacingMessage() {
        let message = APIError.tlsPinningFailed(host: "api.luminavault.fyi").errorDescription
        XCTAssertNotNil(message)
        XCTAssertFalse(message?.isEmpty ?? true)
    }

    // MARK: - Host scoping

    /// Pinning applies to the managed host only. BYO / Tailscale / localhost
    /// endpoints are user-chosen and often self-signed; pinning them would
    /// brick self-hosters.
    func testPinningIsScopedToTheManagedHost() {
        XCTAssertEqual(URLSession.lvManagedHost, "api.luminavault.fyi")

        let unpinned = CertificatePinningDelegate(pinnedHost: nil)
        let challenge = URLAuthenticationChallenge(
            protectionSpace: URLProtectionSpace(
                host: "vault.example.ts.net",
                port: 443,
                protocol: NSURLProtectionSpaceHTTPS,
                realm: nil,
                authenticationMethod: NSURLAuthenticationMethodServerTrust,
            ),
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: NoopChallengeSender(),
        )

        let expectation = expectation(description: "disposition")
        var disposition: URLSession.AuthChallengeDisposition?
        unpinned.urlSession(.shared, didReceive: challenge) { result, _ in
            disposition = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(disposition, .performDefaultHandling)
        XCTAssertFalse(PinningFailureLog.hasRecentFailure())
    }
}

/// `URLAuthenticationChallenge` requires a sender; none of these tests respond
/// through it.
private final class NoopChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}
