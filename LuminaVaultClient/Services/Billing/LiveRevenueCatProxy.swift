// LuminaVaultClient/LuminaVaultClient/Services/Billing/LiveRevenueCatProxy.swift
//
// HER-185 — production `PurchasesProxy` conformance. Single file outside the
// app entrypoint that imports `RevenueCat`. The rest of the app talks to the
// protocol so tests can drop in a `MockPurchasesProxy` without pulling RC in.

import Foundation
import RevenueCat

struct LiveRevenueCatProxy: PurchasesProxy {
    func logIn(_ userID: String) async throws {
        _ = try await Purchases.shared.logIn(userID)
    }

    func logOut() async throws {
        _ = try await Purchases.shared.logOut()
    }

    func customerInfo() async throws -> RCCustomerInfoSnapshot {
        let info = try await Purchases.shared.customerInfo()
        return Self.snapshot(from: info)
    }

    func customerInfoStream() -> AsyncStream<RCCustomerInfoSnapshot> {
        AsyncStream { continuation in
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
