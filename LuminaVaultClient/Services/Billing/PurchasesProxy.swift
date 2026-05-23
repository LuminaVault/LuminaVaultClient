// LuminaVaultClient/LuminaVaultClient/Services/Billing/PurchasesProxy.swift
//
// HER-185 — thin seam over RevenueCat's `Purchases.shared` static surface.
// `BillingService` talks to this protocol only so unit tests can substitute
// a deterministic mock without dragging the RC SDK into the test target.
// The production conformance lives in `LiveRevenueCatProxy.swift`, which is
// the single file outside the app entrypoint that imports `RevenueCat`.

import Foundation

/// Snapshot of the RC `CustomerInfo` fields `BillingService` actually
/// consumes. RC's `CustomerInfo` is not `Sendable` and is reference-typed;
/// flattening into this value type keeps the service strict-concurrency
/// clean and decouples tests from the SDK shape.
struct RCCustomerInfoSnapshot: Sendable, Equatable {
    /// RC entitlement identifiers currently active for the user. Maps onto
    /// `UserTier` via `BillingService.inferredTier(from:)` for the optimistic
    /// post-purchase window before the webhook lands server-side.
    let activeEntitlementIDs: Set<String>
    /// The `app_user_id` RC associates with the snapshot. Useful for asserting
    /// in tests that `logIn` actually updated the underlying SDK identity.
    let originalAppUserID: String
}

/// Outcome of a `purchase(productID:)` call. RC distinguishes a user-cancelled
/// sheet from a real error; we surface both so the UI can stay quiet on cancel
/// and surface a banner on error.
enum RCPurchaseResult: Sendable {
    case success(RCCustomerInfoSnapshot)
    case userCancelled
}

protocol PurchasesProxy: Sendable {
    /// Bind the current authenticated user to RC's identity store. Idempotent
    /// across multiple sign-ins of the same `userID`. `userID` is the server's
    /// stable UUID string — anything else (email, RC anonymous ID) drifts and
    /// breaks the webhook → server-truth join.
    func logIn(_ userID: String) async throws

    /// Disassociate the current RC identity. Call from `signOut()` so the
    /// next session starts anonymous until the next `logIn`.
    func logOut() async throws

    /// One-shot fetch of the current customer info snapshot. Used by
    /// `BillingService.bootstrap` and `restorePurchases()`.
    func customerInfo() async throws -> RCCustomerInfoSnapshot

    /// Long-lived stream of customer-info updates pushed by RC (e.g. after
    /// cross-device upgrades, server-driven refreshes, or background sync).
    /// `BillingService` subscribes once and triggers a server refresh on
    /// each event so the UI stays converged with both truths.
    func customerInfoStream() -> AsyncStream<RCCustomerInfoSnapshot>

    /// Present the StoreKit purchase sheet for `productID` and resolve once
    /// RC has confirmed (or the user cancels). Always followed by a server
    /// refresh in `BillingService` — RC tells us "the purchase happened",
    /// but the webhook is what advances server-truth.
    func purchase(productID: String) async throws -> RCPurchaseResult

    /// Restore previously-purchased entitlements (post-reinstall flow).
    /// Returns the updated snapshot so the service can reconcile against
    /// server-truth in a single round-trip.
    func restorePurchases() async throws -> RCCustomerInfoSnapshot
}
