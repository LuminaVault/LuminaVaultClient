// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockPurchasesProxy.swift
// HER-185 — scripted PurchasesProxy fake. Lets BillingServiceTests drive
// every code path without the RevenueCat SDK actually running.

@testable import LuminaVaultClient
import Foundation

final class MockPurchasesProxy: PurchasesProxy, @unchecked Sendable {
    // MARK: - Scripted results

    var logInResult: Result<Void, Error> = .success(())
    var logOutResult: Result<Void, Error> = .success(())
    var customerInfoResult: Result<RCCustomerInfoSnapshot, Error> = .success(.empty)
    var purchaseResult: Result<RCPurchaseResult, Error> = .success(.success(.empty))
    var restoreResult: Result<RCCustomerInfoSnapshot, Error> = .success(.empty)

    // MARK: - Call recording

    private(set) var logInCalls: [String] = []
    private(set) var logOutCalls = 0
    private(set) var customerInfoCalls = 0
    private(set) var purchaseCalls: [String] = []
    private(set) var restoreCalls = 0

    // MARK: - Stream control

    /// Continuation for the live stream. Tests push snapshots via
    /// `pushStreamEvent(_:)`; `closeStream()` ends the stream so the
    /// `BillingService` subscription task terminates.
    private var streamContinuation: AsyncStream<RCCustomerInfoSnapshot>.Continuation?
    private(set) var streamStartCount = 0

    func pushStreamEvent(_ snapshot: RCCustomerInfoSnapshot) {
        streamContinuation?.yield(snapshot)
    }

    func closeStream() {
        streamContinuation?.finish()
        streamContinuation = nil
    }

    // MARK: - PurchasesProxy

    func logIn(_ userID: String) async throws {
        logInCalls.append(userID)
        _ = try logInResult.get()
    }

    func logOut() async throws {
        logOutCalls += 1
        _ = try logOutResult.get()
    }

    func customerInfo() async throws -> RCCustomerInfoSnapshot {
        customerInfoCalls += 1
        return try customerInfoResult.get()
    }

    func customerInfoStream() -> AsyncStream<RCCustomerInfoSnapshot> {
        streamStartCount += 1
        return AsyncStream { continuation in
            self.streamContinuation = continuation
        }
    }

    func purchase(productID: String) async throws -> RCPurchaseResult {
        purchaseCalls.append(productID)
        return try purchaseResult.get()
    }

    func restorePurchases() async throws -> RCCustomerInfoSnapshot {
        restoreCalls += 1
        return try restoreResult.get()
    }
}

extension RCCustomerInfoSnapshot {
    /// Empty snapshot (no active entitlements, anonymous RC ID). Used as
    /// the default for un-customised tests.
    static let empty = RCCustomerInfoSnapshot(
        activeEntitlementIDs: [],
        originalAppUserID: ""
    )

    /// Convenience builder for tests that want a specific tier inferred.
    static func with(entitlements: Set<String>, userID: String = "user-abc") -> RCCustomerInfoSnapshot {
        RCCustomerInfoSnapshot(activeEntitlementIDs: entitlements, originalAppUserID: userID)
    }
}
