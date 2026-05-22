// LuminaVaultClient/LuminaVaultClientTests/BillingServiceTests.swift
//
// HER-185 — covers BillingService reconciliation between server-truth
// (GET /v1/auth/me/billing) and SDK-truth (RC CustomerInfo snapshot).

import XCTest
@testable import LuminaVaultClient
import LuminaVaultShared

@MainActor
final class BillingServiceTests: XCTestCase {

    // MARK: - bootstrap

    func testBootstrapLogsInThenFetchesServer() async {
        let client = MockBillingClient()
        client.fetchResult = .success(MeBillingResponse(
            tier: .pro,
            tierOverride: nil,
            inTrial: false,
            daysRemaining: nil,
            enforcementEnabled: true
        ))
        let proxy = MockPurchasesProxy()
        let svc = BillingService(client: client, purchases: proxy)
        let userID = UUID()

        await svc.bootstrap(userID: userID)

        XCTAssertEqual(proxy.logInCalls, [userID.uuidString])
        XCTAssertEqual(client.fetchCalls, 1)
        XCTAssertEqual(svc.currentTier, .pro)
        XCTAssertFalse(svc.inTrial)
        XCTAssertTrue(svc.enforcementEnabled)
        XCTAssertTrue(svc.isStreamingCustomerInfo)

        // Tidy: end the stream so the subscription task exits.
        proxy.closeStream()
    }

    func testBootstrapTolerantOfRCLoginFailure() async {
        let client = MockBillingClient()
        client.fetchResult = .success(MeBillingResponse(
            tier: .trial, tierOverride: nil, inTrial: true,
            daysRemaining: 14, enforcementEnabled: true
        ))
        let proxy = MockPurchasesProxy()
        proxy.logInResult = .failure(NSError(domain: "rc", code: 1))
        let svc = BillingService(client: client, purchases: proxy)

        await svc.bootstrap(userID: UUID())

        // Server-truth still lands even though RC login failed. The
        // lastError set during logIn is cleared by the subsequent
        // successful refresh — that's intentional (each operation's
        // surfaceable error reflects its own outcome).
        XCTAssertEqual(svc.currentTier, .trial)
        XCTAssertEqual(svc.daysRemaining, 14)
        XCTAssertTrue(svc.isStreamingCustomerInfo, "stream must start regardless of RC login outcome")
        XCTAssertEqual(client.fetchCalls, 1)
        proxy.closeStream()
    }

    // MARK: - server-truth wins

    func testRefreshFromServerOverwritesOptimisticTier() async {
        let client = MockBillingClient()
        let proxy = MockPurchasesProxy()
        let svc = BillingService(client: client, purchases: proxy)

        // Bootstrap with server-truth = pro.
        client.fetchResult = .success(MeBillingResponse(
            tier: .pro, tierOverride: nil, inTrial: false,
            daysRemaining: nil, enforcementEnabled: true
        ))
        await svc.bootstrap(userID: UUID())
        XCTAssertEqual(svc.currentTier, .pro)

        // Server later flips to lapsed. Refresh must follow even if local
        // RC snapshot would suggest otherwise.
        client.fetchResult = .success(MeBillingResponse(
            tier: .lapsed, tierOverride: nil, inTrial: false,
            daysRemaining: nil, enforcementEnabled: true
        ))
        await svc.refreshFromServer()
        XCTAssertEqual(svc.currentTier, .lapsed)
        proxy.closeStream()
    }

    // MARK: - optimistic upgrade

    /// End-to-end: purchase succeeds, server eventually agrees. Tier
    /// ends at the new value. The optimistic-vs-server-truth ordering
    /// is exercised explicitly in
    /// `testPurchaseOptimisticUpgradeSurvivesRefreshFailure` below.
    func testPurchaseAdvancesTierWhenServerAgrees() async {
        let client = MockBillingClient()
        // Initial server-truth: trial.
        client.fetchResult = .success(MeBillingResponse(
            tier: .trial, tierOverride: nil, inTrial: true,
            daysRemaining: 14, enforcementEnabled: true
        ))
        let proxy = MockPurchasesProxy()
        let svc = BillingService(client: client, purchases: proxy)
        await svc.bootstrap(userID: UUID())
        XCTAssertEqual(svc.currentTier, .trial)

        // Webhook has now landed server-side: subsequent fetches return pro.
        client.fetchResult = .success(MeBillingResponse(
            tier: .pro, tierOverride: nil, inTrial: false,
            daysRemaining: nil, enforcementEnabled: true
        ))
        proxy.purchaseResult = .success(.success(
            .with(entitlements: [RCEntitlement.pro])
        ))

        await svc.purchase(productID: "lv_pro_monthly_1499")

        XCTAssertEqual(svc.currentTier, .pro)
        XCTAssertFalse(svc.isPurchaseInFlight)
        XCTAssertEqual(proxy.purchaseCalls, ["lv_pro_monthly_1499"])
        proxy.closeStream()
    }

    /// Hot-path coverage of the optimistic semantic: RC reports the pro
    /// entitlement post-purchase, but the server hasn't seen the webhook
    /// yet AND the refresh call itself fails (transient network). The
    /// service must keep the optimistic upgrade so the UI doesn't snap
    /// back to trial.
    func testPurchaseOptimisticUpgradeSurvivesRefreshFailure() async {
        let client = MockBillingClient()
        // Initial server-truth: trial.
        client.fetchResult = .success(MeBillingResponse(
            tier: .trial, tierOverride: nil, inTrial: true,
            daysRemaining: 14, enforcementEnabled: true
        ))
        let proxy = MockPurchasesProxy()
        let svc = BillingService(client: client, purchases: proxy)
        await svc.bootstrap(userID: UUID())
        XCTAssertEqual(svc.currentTier, .trial)

        // Purchase succeeds via RC; post-purchase refresh fails.
        proxy.purchaseResult = .success(.success(
            .with(entitlements: [RCEntitlement.pro])
        ))
        client.fetchResult = .failure(NSError(domain: "net", code: -1))

        await svc.purchase(productID: "lv_pro_monthly_1499")

        XCTAssertEqual(svc.currentTier, .pro,
            "optimistic upgrade from RC must survive a failed post-purchase refresh")
        XCTAssertNotNil(svc.lastError)
        proxy.closeStream()
    }

    func testPurchaseUserCancelledLeavesTierUnchanged() async {
        let client = MockBillingClient()
        client.fetchResult = .success(MeBillingResponse(
            tier: .trial, tierOverride: nil, inTrial: true,
            daysRemaining: 14, enforcementEnabled: true
        ))
        let proxy = MockPurchasesProxy()
        let svc = BillingService(client: client, purchases: proxy)
        await svc.bootstrap(userID: UUID())

        proxy.purchaseResult = .success(.userCancelled)
        await svc.purchase(productID: "lv_pro_monthly_1499")

        XCTAssertEqual(svc.currentTier, .trial)
        XCTAssertNil(svc.lastError)
        proxy.closeStream()
    }

    // MARK: - restore

    func testRestorePurchasesAppliesSnapshotThenRefreshes() async {
        let client = MockBillingClient()
        // Server agrees: ultimate.
        client.fetchResult = .success(MeBillingResponse(
            tier: .ultimate, tierOverride: nil, inTrial: false,
            daysRemaining: nil, enforcementEnabled: true
        ))
        let proxy = MockPurchasesProxy()
        proxy.restoreResult = .success(.with(entitlements: [RCEntitlement.ultimate]))
        let svc = BillingService(client: client, purchases: proxy)
        await svc.bootstrap(userID: UUID())
        // After bootstrap, fetchCalls == 1.

        await svc.restorePurchases()

        XCTAssertEqual(proxy.restoreCalls, 1)
        XCTAssertGreaterThanOrEqual(client.fetchCalls, 2, "restore should trigger a server refresh")
        XCTAssertEqual(svc.currentTier, .ultimate)
        proxy.closeStream()
    }

    // MARK: - teardown

    func testTeardownLogsOutAndResets() async {
        let client = MockBillingClient()
        client.fetchResult = .success(MeBillingResponse(
            tier: .pro, tierOverride: nil, inTrial: false,
            daysRemaining: nil, enforcementEnabled: true
        ))
        let proxy = MockPurchasesProxy()
        let svc = BillingService(client: client, purchases: proxy)
        await svc.bootstrap(userID: UUID())
        XCTAssertTrue(svc.isStreamingCustomerInfo)

        await svc.teardown()

        XCTAssertEqual(proxy.logOutCalls, 1)
        XCTAssertEqual(svc.currentTier, .trial)
        XCTAssertNil(svc.daysRemaining)
        XCTAssertFalse(svc.inTrial)
        XCTAssertFalse(svc.enforcementEnabled)
        XCTAssertFalse(svc.isStreamingCustomerInfo)
        proxy.closeStream()
    }

    // MARK: - soft failure when refresh errors

    func testRefreshFailureRecordsErrorButKeepsState() async {
        let client = MockBillingClient()
        client.fetchResult = .success(MeBillingResponse(
            tier: .pro, tierOverride: nil, inTrial: false,
            daysRemaining: nil, enforcementEnabled: true
        ))
        let proxy = MockPurchasesProxy()
        let svc = BillingService(client: client, purchases: proxy)
        await svc.bootstrap(userID: UUID())

        client.fetchResult = .failure(NSError(domain: "net", code: -1))
        await svc.refreshFromServer()

        XCTAssertEqual(svc.currentTier, .pro, "prior server-truth survives a transient failure")
        XCTAssertNotNil(svc.lastError)
        proxy.closeStream()
    }

    // MARK: - inferredTier mapping

    func testInferredTierPrefersUltimateOverPro() {
        let snap = RCCustomerInfoSnapshot.with(
            entitlements: [RCEntitlement.pro, RCEntitlement.ultimate]
        )
        XCTAssertEqual(BillingService.inferredTier(from: snap), .ultimate)
    }

    func testInferredTierTrialWhenNoActiveEntitlement() {
        XCTAssertEqual(BillingService.inferredTier(from: .empty), .trial)
    }
}
