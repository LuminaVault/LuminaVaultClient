// LuminaVaultClient/LuminaVaultClientTests/TrialCountdownBannerVisibilityTests.swift
//
// HER-211 — pure logic test for the trial countdown banner. Render
// behaviour is covered by snapshot tests in a follow-up; this file
// asserts the inclusion/exclusion rule:
//
//   shouldShow == true   iff   billing != nil
//                          AND  billing.inTrial == true
//                          AND  billing.currentTier == .trial
//                          AND  billing.daysRemaining != nil
//                          AND  billing.daysRemaining < 5

import XCTest
@testable import LuminaVaultClient
import LuminaVaultShared

@MainActor
final class TrialCountdownBannerVisibilityTests: XCTestCase {

    // MARK: - Positive cases (banner shown)

    func testShownWithFourDaysLeft() async {
        let svc = await billingService(tier: .trial, inTrial: true, days: 4)
        XCTAssertTrue(TrialCountdownBanner.shouldShow(billing: svc))
    }

    func testShownWithZeroDaysLeft() async {
        // Day-of-expiry: still in trial, still must convert today.
        let svc = await billingService(tier: .trial, inTrial: true, days: 0)
        XCTAssertTrue(TrialCountdownBanner.shouldShow(billing: svc))
    }

    func testShownWithOneDayLeft() async {
        let svc = await billingService(tier: .trial, inTrial: true, days: 1)
        XCTAssertTrue(TrialCountdownBanner.shouldShow(billing: svc))
    }

    // MARK: - Boundary

    func testHiddenAtThresholdFiveDays() async {
        // `< 5` is strict; exactly 5 days remaining must NOT show the
        // urgency banner.
        let svc = await billingService(tier: .trial, inTrial: true, days: 5)
        XCTAssertFalse(TrialCountdownBanner.shouldShow(billing: svc))
    }

    func testHiddenWithTenDaysLeft() async {
        let svc = await billingService(tier: .trial, inTrial: true, days: 10)
        XCTAssertFalse(TrialCountdownBanner.shouldShow(billing: svc))
    }

    // MARK: - Negative cases

    func testHiddenWhenNotInTrial() async {
        // Server says days remaining but inTrial=false (e.g. paid pro
        // with grace period). Banner shouldn't fire.
        let svc = await billingService(tier: .pro, inTrial: false, days: 2)
        XCTAssertFalse(TrialCountdownBanner.shouldShow(billing: svc))
    }

    func testHiddenWhenTierNotTrial() async {
        // Pro user with inTrial=true (shouldn't happen in practice but
        // the rule is conservative — require both flags).
        let svc = await billingService(tier: .pro, inTrial: true, days: 3)
        XCTAssertFalse(TrialCountdownBanner.shouldShow(billing: svc))
    }

    func testHiddenWhenDaysRemainingNil() async {
        let svc = await billingService(tier: .trial, inTrial: true, days: nil)
        XCTAssertFalse(TrialCountdownBanner.shouldShow(billing: svc))
    }

    func testHiddenWhenBillingServiceNil() {
        // Cold launch / unauthenticated path.
        XCTAssertFalse(TrialCountdownBanner.shouldShow(billing: nil))
    }

    // MARK: - Helpers

    private func billingService(
        tier: UserTier,
        inTrial: Bool,
        days: Int?
    ) async -> BillingService {
        let client = MockBillingClient()
        client.fetchResult = .success(MeBillingResponse(
            tier: tier,
            tierOverride: nil,
            inTrial: inTrial,
            daysRemaining: days,
            enforcementEnabled: true
        ))
        let proxy = MockPurchasesProxy()
        let svc = BillingService(client: client, purchases: proxy)
        await svc.bootstrap(userID: UUID())
        proxy.closeStream()
        return svc
    }
}

// MARK: - RCProduct sanity (HER-211)

final class RCProductTests: XCTestCase {
    func testAllListContainsFourUniqueIdentifiers() {
        XCTAssertEqual(RCProduct.all.count, 4)
        XCTAssertEqual(Set(RCProduct.all).count, 4, "no duplicate product IDs")
    }

    func testProductIDsMatchSpec() {
        XCTAssertEqual(RCProduct.proMonthly,      "pro_monthly_14_99")
        XCTAssertEqual(RCProduct.proYearly,       "pro_yearly_149_99")
        XCTAssertEqual(RCProduct.ultimateMonthly, "ultimate_monthly_29_99")
        XCTAssertEqual(RCProduct.ultimateYearly,  "ultimate_yearly_299_99")
    }
}
