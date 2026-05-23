// LuminaVaultClient/LuminaVaultClientTests/AppStateBillingHookTests.swift
//
// HER-185 — verifies `AppState.handleAuthSuccess(_:)` constructs a
// `BillingService` bound to the authenticated user, and that
// `signOut()` tears it down. Uses the `purchasesProxyFactory` seam to
// drop a `MockPurchasesProxy` in place of the live RC adapter.

import XCTest
@testable import LuminaVaultClient

@MainActor
final class AppStateBillingHookTests: XCTestCase {
    private var state: AppState!
    private var proxy: MockPurchasesProxy!

    override func setUp() {
        super.setUp()
        proxy = MockPurchasesProxy()
        let capturedProxy = proxy!
        state = AppState(keychain: KeychainService(service: "test.her185.\(UUID().uuidString)"))
        state.purchasesProxyFactory = { capturedProxy }
    }

    func testHandleAuthSuccessConstructsBillingServiceAndCallsLogIn() async {
        XCTAssertNil(state.billingService)

        state.handleAuthSuccess(.stub)

        XCTAssertNotNil(state.billingService, "billing service must be wired post sign-in")

        // `bootstrap` runs in a detached Task; spin briefly to let it land.
        await waitUntil(timeout: 2.0) { [proxy] in
            (proxy?.logInCalls.first) != nil
        }

        let expectedID = AuthResponse.stub.userId.uuidString
        XCTAssertEqual(proxy.logInCalls, [expectedID])
    }

    func testSignOutTearsDownBillingService() async {
        state.handleAuthSuccess(.stub)
        XCTAssertNotNil(state.billingService)

        // Let bootstrap settle so teardown observes a live stream.
        await waitUntil(timeout: 2.0) { [proxy] in
            (proxy?.logInCalls.first) != nil
        }

        await state.signOut()

        XCTAssertNil(state.billingService, "service reference must be cleared on sign-out")
        await waitUntil(timeout: 2.0) { [proxy] in
            (proxy?.logOutCalls ?? 0) > 0
        }
        XCTAssertEqual(proxy.logOutCalls, 1)
    }

    // MARK: - helpers

    /// Polls `predicate` until it returns true or `timeout` elapses. Used
    /// instead of arbitrary `Task.sleep` so the test fails fast if the
    /// expectation never lands.
    private func waitUntil(timeout: TimeInterval, _ predicate: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out after \(timeout)s waiting for predicate")
    }
}
