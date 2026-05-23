// LuminaVaultClient/LuminaVaultClientTests/UniversalPaywallInterceptorTests.swift
//
// HER-211 — covers the BaseHTTPClient onPaymentRequired callback that
// drives the root-level paywall sheet in `LuminaVaultClientApp`. Every
// 402 must fire the callback, regardless of whether the call site
// catches `APIError.paymentRequired`. The throw still happens — the
// callback is additive, not a replacement.

import XCTest
@testable import LuminaVaultClient
import LuminaVaultShared

final class UniversalPaywallInterceptorTests: XCTestCase {
    private struct GatedEndpoint: Endpoint {
        typealias Response = EmptyResponse
        var path: String { "/gated" }
        var method: HTTPMethod { .get }
        var requiresAuth: Bool { false }
    }

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - Callback fires with parsed body

    func testOnPaymentRequiredReceivesParsedHints() async {
        MockURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://test.local/gated")!,
                statusCode: 402, httpVersion: nil, headerFields: nil
            )!
            let body = #"{"paywall_id":"ultimate_upsell","required_tier":"ultimate"}"#
            return (response, Data(body.utf8))
        }

        let captured = CallbackCaptureBox()
        let client = BaseHTTPClient(
            session: session,
            onPaymentRequired: { paywallID, requiredTier in
                await captured.record(paywallID: paywallID, requiredTier: requiredTier)
            }
        )

        do {
            _ = try await client.execute(GatedEndpoint())
            XCTFail("Expected APIError.paymentRequired to be thrown")
        } catch APIError.paymentRequired {
            // Expected — the throw still happens.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let snapshot = await captured.snapshot()
        XCTAssertEqual(snapshot.callCount, 1, "callback must fire exactly once per 402")
        XCTAssertEqual(snapshot.lastPaywallID, "ultimate_upsell")
        XCTAssertEqual(snapshot.lastRequiredTier, .ultimate)
    }

    // MARK: - Bare 402 still fires callback

    func testOnPaymentRequiredFiresEvenWithoutBodyHints() async {
        MockURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://test.local/gated")!,
                statusCode: 402, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())  // empty body
        }

        let captured = CallbackCaptureBox()
        let client = BaseHTTPClient(
            session: session,
            onPaymentRequired: { paywallID, requiredTier in
                await captured.record(paywallID: paywallID, requiredTier: requiredTier)
            }
        )

        do {
            _ = try await client.execute(GatedEndpoint())
            XCTFail("Expected APIError.paymentRequired")
        } catch APIError.paymentRequired(let paywallID, let tier) {
            XCTAssertNil(paywallID)
            XCTAssertNil(tier)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let snapshot = await captured.snapshot()
        XCTAssertEqual(snapshot.callCount, 1)
        XCTAssertNil(snapshot.lastPaywallID)
        XCTAssertNil(snapshot.lastRequiredTier)
    }

    // MARK: - Callback NOT fired on non-402

    func testOnPaymentRequiredSkippedOnUnrelatedError() async {
        MockURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://test.local/gated")!,
                statusCode: 500, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("server boom".utf8))
        }

        let captured = CallbackCaptureBox()
        let client = BaseHTTPClient(
            session: session,
            onPaymentRequired: { paywallID, requiredTier in
                await captured.record(paywallID: paywallID, requiredTier: requiredTier)
            }
        )

        do {
            _ = try await client.execute(GatedEndpoint())
            XCTFail("Expected APIError.httpError")
        } catch APIError.httpError(let code, _) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let snapshot = await captured.snapshot()
        XCTAssertEqual(snapshot.callCount, 0, "402-only callback must not fire on 500")
    }

    // MARK: - Backwards compat: no callback configured

    func testThrowStillPropagatesWithoutCallback() async {
        MockURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://test.local/gated")!,
                statusCode: 402, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
        let client = BaseHTTPClient(session: session)  // no onPaymentRequired
        do {
            _ = try await client.execute(GatedEndpoint())
            XCTFail("Expected APIError.paymentRequired")
        } catch APIError.paymentRequired {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Capture box

/// Actor so concurrent callbacks don't race; the test reads a snapshot
/// once the awaited `execute(_:)` returns.
private actor CallbackCaptureBox {
    private(set) var callCount = 0
    private(set) var lastPaywallID: String?
    private(set) var lastRequiredTier: UserTier?

    struct Snapshot: Sendable {
        let callCount: Int
        let lastPaywallID: String?
        let lastRequiredTier: UserTier?
    }

    func record(paywallID: String?, requiredTier: UserTier?) {
        callCount += 1
        lastPaywallID = paywallID
        lastRequiredTier = requiredTier
    }

    func snapshot() -> Snapshot {
        Snapshot(
            callCount: callCount,
            lastPaywallID: lastPaywallID,
            lastRequiredTier: lastRequiredTier
        )
    }
}
