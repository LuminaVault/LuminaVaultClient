// LuminaVaultClient/LuminaVaultClientTests/PaywallOfferingResolverTests.swift
//
// The paywall used to render a mascot, a large gap, and a Close button
// whenever RevenueCat could not produce an offering — three unrelated causes
// collapsed into one screen with no retry and a swallowed error. These pin the
// three apart, because the correct copy and the correct affordance differ for
// each: one is expected and benign, one is transient and retryable, one is a
// dashboard gap that retrying cannot fix.

import XCTest
@testable import LuminaVaultClient

final class PaywallOfferingResolverTests: XCTestCase {
    /// The normal TestFlight state: `Config.Beta.xcconfig` ships an empty
    /// `LV_RC_API_KEY` deliberately, so `Purchases.configure` never runs.
    func testUnconfiguredSDKIsNotConfigured() {
        let state = PaywallOfferingResolver.state(
            isConfigured: false, fetchFailure: nil, availablePackageCount: nil
        )
        XCTAssertEqual(state, .notConfigured)
    }

    /// An unconfigured SDK never fetched anything, so a stale package count
    /// must not promote it to `.available`.
    func testUnconfiguredWinsOverEverythingElse() {
        let state = PaywallOfferingResolver.state(
            isConfigured: false, fetchFailure: "boom", availablePackageCount: 3
        )
        XCTAssertEqual(state, .notConfigured)
    }

    func testThrownFetchCarriesItsReason() {
        let state = PaywallOfferingResolver.state(
            isConfigured: true,
            fetchFailure: "The Internet connection appears to be offline.",
            availablePackageCount: nil
        )
        XCTAssertEqual(state, .fetchFailed("The Internet connection appears to be offline."))
    }

    /// No offering matched — neither `current` nor the server's `paywall_id`.
    func testNoMatchingOfferingIsEmpty() {
        let state = PaywallOfferingResolver.state(
            isConfigured: true, fetchFailure: nil, availablePackageCount: nil
        )
        XCTAssertEqual(state, .empty)
    }

    /// The case that produced the original blank sheet: an offering exists and
    /// the fetch succeeded, but it carries no packages, so RevenueCatUI renders
    /// nothing at all.
    func testOfferingWithNoPackagesIsEmpty() {
        let state = PaywallOfferingResolver.state(
            isConfigured: true, fetchFailure: nil, availablePackageCount: 0
        )
        XCTAssertEqual(state, .empty)
    }

    func testConfiguredOfferingWithPackagesIsAvailable() {
        let state = PaywallOfferingResolver.state(
            isConfigured: true, fetchFailure: nil, availablePackageCount: 2
        )
        XCTAssertEqual(state, .available)
        XCTAssertTrue(state.showsStorePaywall)
    }

    /// Only `.available` may hand off to RevenueCatUI. Its `PaywallView`
    /// builds RC's error view with `releaseBehavior: .fatalError`, so
    /// rendering it in any other state is an EXC_BREAKPOINT in a release
    /// build — the guard is load-bearing, not cosmetic.
    func testOnlyAvailableRendersTheStorePaywall() {
        let others: [PaywallOfferingState] = [
            .checking, .notConfigured, .fetchFailed("x"), .empty,
        ]
        for state in others {
            XCTAssertFalse(state.showsStorePaywall, "\(state) must not render RevenueCatUI")
        }
    }

    /// Every failure is reported, and the three are distinguishable. Without
    /// this they are one undifferentiated "paywall didn't show" in production.
    func testEveryFailureReportsADistinctReason() {
        XCTAssertNil(PaywallOfferingState.checking.telemetryReason)
        XCTAssertNil(PaywallOfferingState.available.telemetryReason)

        let reasons = [
            PaywallOfferingState.notConfigured.telemetryReason,
            PaywallOfferingState.fetchFailed("x").telemetryReason,
            PaywallOfferingState.empty.telemetryReason,
        ].compactMap { $0 }

        XCTAssertEqual(reasons.count, 3)
        XCTAssertEqual(Set(reasons).count, 3, "failure reasons must be distinguishable")
    }
}
