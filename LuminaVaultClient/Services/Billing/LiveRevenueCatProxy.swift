// LuminaVaultClient/LuminaVaultClient/Services/Billing/LiveRevenueCatProxy.swift
//
// HER-185 — production `PurchasesProxy` conformance. Single file outside the
// app entrypoint that imports `RevenueCat`. The rest of the app talks to the
// protocol so tests can drop in a `MockPurchasesProxy` without pulling RC in.
//
// Every method guards on `Purchases.isConfigured` because the app may boot
// without an RC public key (Debug schemes without `REVENUECAT_PUBLIC_KEY`,
// TestFlight builds before HER-271 ASC config lands, env unwinds). When
// unconfigured, RC's `Purchases.shared` accessor traps via `fatalError`,
// so we MUST NOT touch it. Soft-no-op semantics match HER-185 intent:
// "BillingService treats that as a soft failure and falls back to
// server-truth only" (`Config.swift:32-35`).

import Foundation
import RevenueCat

/// Thrown when a `purchase(productID:)` call is made while RC is not
/// configured. Callers (PaywallView / SubscriptionView) surface this as
/// "subscriptions unavailable on this device" instead of crashing.
struct BillingUnavailableError: LocalizedError {
    var errorDescription: String? {
        "Subscriptions are unavailable in this build. Please update the app."
    }
}

struct LiveRevenueCatProxy: PurchasesProxy {
    /// Empty snapshot returned when `Purchases.shared` isn't safe to touch.
    /// Anonymous `originalAppUserID` matches what RC returns before
    /// `logIn` runs, so consumers don't special-case the no-RC path.
    private static let emptySnapshot = RCCustomerInfoSnapshot(
        activeEntitlementIDs: [],
        originalAppUserID: ""
    )

    func logIn(_ userID: String) async throws {
        guard Purchases.isConfigured else { return }
        _ = try await Purchases.shared.logIn(userID)
    }

    func logOut() async throws {
        guard Purchases.isConfigured else { return }
        _ = try await Purchases.shared.logOut()
    }

    func customerInfo() async throws -> RCCustomerInfoSnapshot {
        guard Purchases.isConfigured else { return Self.emptySnapshot }
        let info = try await Purchases.shared.customerInfo()
        return Self.snapshot(from: info)
    }

    func customerInfoStream() -> AsyncStream<RCCustomerInfoSnapshot> {
        guard Purchases.isConfigured else {
            // Empty, finished stream — `BillingService.startCustomerInfoStream`
            // exits its for-await loop cleanly without ever firing
            // `applyOptimistic` / `refreshFromServer`.
            return AsyncStream { $0.finish() }
        }
        return AsyncStream { continuation in
            let task = Task {
                for await info in Purchases.shared.customerInfoStream {
                    continuation.yield(Self.snapshot(from: info))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func purchase(productID: String) async throws -> RCPurchaseResult {
        guard Purchases.isConfigured else { throw BillingUnavailableError() }
        guard let product = try await Purchases.shared.products([productID]).first else {
            throw NSError(
                domain: "PurchasesProxy",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Product \(productID) not found in store"]
            )
        }
        let result = try await Purchases.shared.purchase(product: product)
        if result.userCancelled {
            return .userCancelled
        }
        return .success(Self.snapshot(from: result.customerInfo))
    }

    func restorePurchases() async throws -> RCCustomerInfoSnapshot {
        guard Purchases.isConfigured else { throw BillingUnavailableError() }
        let info = try await Purchases.shared.restorePurchases()
        return Self.snapshot(from: info)
    }

    private static func snapshot(from info: CustomerInfo) -> RCCustomerInfoSnapshot {
        let active = Set(info.entitlements.active.keys)
        return RCCustomerInfoSnapshot(
            activeEntitlementIDs: active,
            originalAppUserID: info.originalAppUserId
        )
    }
}

/// Picks the right `PurchasesProxy` for the current launch. When
/// `Purchases.configure(…)` has run (RC key present + non-empty), returns
/// the live proxy; otherwise returns `NoOpPurchasesProxy` so callers don't
/// trip the SDK's `Purchases.shared` `fatalError`.
///
/// Lives alongside `LiveRevenueCatProxy` because `AppState` must not
/// import `RevenueCat` directly — the proxy seam is the boundary.
enum PurchasesProxyFactory {
    @MainActor
    static func makeDefault() -> any PurchasesProxy {
        Purchases.isConfigured ? LiveRevenueCatProxy() : NoOpPurchasesProxy()
    }
}
