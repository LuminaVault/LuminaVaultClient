// LuminaVaultClient/LuminaVaultClientTests/PostHogEnvTests.swift
// HER-242 — guards the resolution chain so production builds never crash
// on missing PostHog config again.
import XCTest
@testable import LuminaVaultClient

final class PostHogEnvTests: XCTestCase {
    func testProjectTokenAlwaysResolves() {
        XCTAssertNotNil(PostHogEnv.projectToken.value,
                        "Token must fall through to compile-time default; otherwise prod boot crashes")
    }

    func testHostAlwaysResolves() {
        XCTAssertNotNil(PostHogEnv.host.value,
                        "Host must fall through to compile-time default; otherwise prod boot crashes")
    }

    func testTokenDefaultMatchesCommittedSchemeValue() {
        // If the default drifts away from the scheme-committed token, dev and
        // prod will report into different PostHog projects without anyone
        // noticing. Lock the invariant.
        XCTAssertEqual(PostHogEnv.projectToken.value,
                       "phc_uJu7ZqyfuPpDAsWpyzNiPH2pow8kdUfNVQVM2PEUCFGU")
    }

    func testHostDefaultIsUSCluster() {
        XCTAssertEqual(PostHogEnv.host.value, "https://us.i.posthog.com")
    }
}
