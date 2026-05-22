// LuminaVaultClient/LuminaVaultClientTests/EntitlementGateTests.swift
//
// HER-188 — covers the tier-rank helper (`BillingService.meets(_:requires:)`)
// and the SubscriptionViewModel state machine. The SwiftUI modifier itself
// is exercised end-to-end via `SubscriptionViewSnapshotTests` — render-only
// assertions are flakier than direct VM tests, so we keep the unit coverage
// focused on the pure logic.

import XCTest
@testable import LuminaVaultClient
import LuminaVaultShared

@MainActor
final class EntitlementGateTests: XCTestCase {

    // MARK: - Tier ladder

    func testTrialDoesNotMeetProRequirement() {
        XCTAssertFalse(BillingService.meets(.trial, requires: .pro))
    }

    func testProMeetsProRequirement() {
        XCTAssertTrue(BillingService.meets(.pro, requires: .pro))
    }

    func testUltimateMeetsProRequirement() {
        XCTAssertTrue(BillingService.meets(.ultimate, requires: .pro))
    }

    func testProDoesNotMeetUltimateRequirement() {
        XCTAssertFalse(BillingService.meets(.pro, requires: .ultimate))
    }

    func testLapsedDoesNotMeetAnyPaidTier() {
        XCTAssertFalse(BillingService.meets(.lapsed, requires: .pro))
        XCTAssertFalse(BillingService.meets(.lapsed, requires: .ultimate))
        XCTAssertFalse(BillingService.meets(.lapsed, requires: .trial))
    }

    func testArchivedDoesNotMeetEvenTrial() {
        XCTAssertFalse(BillingService.meets(.archived, requires: .trial))
    }

    // MARK: - SubscriptionViewModel

    func testViewModelExposesServerTruth() async {
        let svc = await makeBillingService(serverTier: .pro, inTrial: false, days: nil)
        await svc.bootstrap(userID: UUID())
        let vm = SubscriptionViewModel(billing: svc)

        XCTAssertEqual(vm.currentTier, .pro)
        XCTAssertFalse(vm.inTrial)
        XCTAssertNil(vm.daysRemaining)
        // Pro can still upgrade to ultimate.
        XCTAssertTrue(vm.canUpgrade)
    }

    func testUltimateUserHasNoUpsell() async {
        let svc = await makeBillingService(serverTier: .ultimate, inTrial: false, days: nil)
        await svc.bootstrap(userID: UUID())
        let vm = SubscriptionViewModel(billing: svc)

        XCTAssertFalse(vm.canUpgrade)
    }

    func testTapUpgradePresentsDefaultPaywall() async {
        let svc = await makeBillingService(serverTier: .trial, inTrial: true, days: 14)
        await svc.bootstrap(userID: UUID())
        let vm = SubscriptionViewModel(billing: svc)

        XCTAssertNil(vm.presentedPaywallID)
        vm.tapUpgrade()
        XCTAssertEqual(vm.presentedPaywallID, "default")
    }

    func testDismissPaywallClearsState() async {
        let vm = SubscriptionViewModel(billing: nil)
        vm.presentedPaywallID = "default"
        vm.dismissPaywall()
        XCTAssertNil(vm.presentedPaywallID)
    }

    func testRestoreWithoutBillingServiceSurfacesError() async {
        let vm = SubscriptionViewModel(billing: nil)
        await vm.restorePurchases()
        XCTAssertNotNil(vm.restoreErrorMessage)
    }

    // MARK: - Helpers

    private func makeBillingService(
        serverTier: UserTier,
        inTrial: Bool,
        days: Int?
    ) async -> BillingService {
        let client = MockBillingClient()
        client.fetchResult = .success(MeBillingResponse(
            tier: serverTier,
            tierOverride: nil,
            inTrial: inTrial,
            daysRemaining: days,
            enforcementEnabled: true
        ))
        let proxy = MockPurchasesProxy()
        return BillingService(client: client, purchases: proxy)
    }
}

// MARK: - APIError.paymentRequired decoding

final class PaymentRequiredBodyTests: XCTestCase {
    func testDecodesFullBody() throws {
        let json = """
        { "paywall_id": "ultimate_upsell", "required_tier": "ultimate" }
        """.data(using: .utf8)!
        let body = try JSONDecoder.hvDefault.decode(PaymentRequiredBody.self, from: json)
        XCTAssertEqual(body.paywallID, "ultimate_upsell")
        XCTAssertEqual(body.requiredTier, .ultimate)
    }

    func testTolerantOfMissingFields() throws {
        let json = "{}".data(using: .utf8)!
        let body = try JSONDecoder.hvDefault.decode(PaymentRequiredBody.self, from: json)
        XCTAssertNil(body.paywallID)
        XCTAssertNil(body.requiredTier)
    }

    func testTolerantOfPartialFields() throws {
        let json = """
        { "paywall_id": "default" }
        """.data(using: .utf8)!
        let body = try JSONDecoder.hvDefault.decode(PaymentRequiredBody.self, from: json)
        XCTAssertEqual(body.paywallID, "default")
        XCTAssertNil(body.requiredTier)
    }
}
