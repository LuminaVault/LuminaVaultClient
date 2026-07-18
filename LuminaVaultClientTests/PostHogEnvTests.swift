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

    func testTokenDefaultMatchesCommittedSchemeValue() throws {
        // If the default drifts away from the scheme-committed token, dev and
        // prod will report into different PostHog projects without anyone
        // noticing. Lock the invariant.
        //
        // On CI the real (gitignored) xcconfig is absent, so the build
        // materializes the `.sample`, which injects the placeholder token
        // into Info.plist; `.value` then returns that placeholder ahead of
        // the compile-time default. Skip there — the invariant is only
        // meaningful when a real token is resolved (local dev / signed build).
        let token = PostHogEnv.projectToken.value
        try XCTSkipIf(token == "REPLACE_WITH_POSTHOG_PROJECT_TOKEN",
                      "placeholder token from materialized sample xcconfig (CI)")
        XCTAssertEqual(token, "phc_uJu7ZqyfuPpDAsWpyzNiPH2pow8kdUfNVQVM2PEUCFGU")
    }

    func testHostDefaultIsUSCluster() {
        XCTAssertEqual(PostHogEnv.host.value, "https://us.i.posthog.com")
    }
}
