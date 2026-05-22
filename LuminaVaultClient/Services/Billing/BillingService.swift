// LuminaVaultClient/LuminaVaultClient/Services/Billing/BillingService.swift
//
// HER-185 — single observable surface the UI reads to learn the current
// user's tier + trial state. Reconciles two sources of truth:
//
//   1. Server-truth — GET /v1/auth/me/billing → `MeBillingResponse`. The
//      definitive answer once the RevenueCat S2S webhook has landed.
//   2. SDK-truth   — RC `CustomerInfo` snapshot. Available immediately
//      after a sandbox purchase, before the webhook fires server-side.
//
// Server-truth wins whenever both are available. SDK-truth is used to
// optimistically upgrade the tier between purchase completion and the
// next server refresh so the UI never feels "stuck on trial" during the
// 0-60s reconciliation window.

import Foundation
import LuminaVaultShared

/// RevenueCat entitlement identifiers, as configured in the RC dashboard
/// for the LuminaVault `default` offering. Convention: lower-case
/// `UserTier` rawValue per entitlement. Centralised here so the mapping
/// stays one edit away.
enum RCEntitlement {
    static let pro = "pro"
    static let ultimate = "ultimate"
}

@MainActor
@Observable
final class BillingService {
    /// Current effective tier the UI should render against. Defaults to
    /// `.trial` for fresh installs and during the brief gap between
    /// `init` and `bootstrap`.
    private(set) var currentTier: UserTier = .trial

    /// Days remaining in the active trial. `nil` when not in trial or
    /// when the server hasn't yet reported a value.
    private(set) var daysRemaining: Int?

    /// True for the trial window. Mirrors `MeBillingResponse.inTrial`
    /// directly — RC has no equivalent flag, so this is server-only.
    private(set) var inTrial: Bool = false

    /// True when the server is currently returning 402 on tier-gated
    /// endpoints. Surfaces in the UI so QA can verify the kill-switch.
    private(set) var enforcementEnabled: Bool = false

    /// Last user-surfaceable error from `refreshFromServer` / `purchase` /
    /// `restorePurchases`. Reset on the next successful call.
    private(set) var lastError: String?

    /// True between the start of `purchase(productID:)` and its resolution.
    /// Lets the paywall UI disable the buy button without redoing its own
    /// in-flight tracking.
    private(set) var isPurchaseInFlight: Bool = false

    /// True once a `customerInfoStream` subscription is live. Used in
    /// tests to assert `bootstrap` / `teardown` symmetry.
    private(set) var isStreamingCustomerInfo: Bool = false

    private let client: BillingClientProtocol
    private let purchases: PurchasesProxy
    private var streamTask: Task<Void, Never>?

    init(client: BillingClientProtocol, purchases: PurchasesProxy) {
        self.client = client
        self.purchases = purchases
    }

    /// Bind RC's identity to the server-side user, fetch the authoritative
    /// snapshot, and start listening for RC-pushed updates. Called from
    /// `AppState.handleAuthSuccess(_:)` after PostHog identify so RC and
    /// analytics share the same identity.
    func bootstrap(userID: UUID) async {
        do {
            try await purchases.logIn(userID.uuidString)
        } catch {
            // RC login failure is not a hard stop — server-truth still works.
            lastError = "RevenueCat sign-in failed: \(error.localizedDescription)"
        }
        await refreshFromServer()
        startCustomerInfoStream()
    }

    /// Pull the server-truth snapshot. `MeBillingResponse` wins over any
    /// optimistic SDK-truth state set by a recent `purchase(productID:)`.
    func refreshFromServer() async {
        do {
            let snapshot = try await client.fetchMeBilling()
            applyServerTruth(snapshot)
            lastError = nil
        } catch {
            lastError = "Failed to refresh billing: \(error.localizedDescription)"
        }
    }

    /// Trigger the StoreKit purchase sheet for `productID` via RC. On
    /// success, optimistically upgrade `currentTier` from the RC snapshot
    /// so the UI flips immediately, then re-pull server-truth to converge.
    func purchase(productID: String) async {
        guard !isPurchaseInFlight else { return }
        isPurchaseInFlight = true
        defer { isPurchaseInFlight = false }

        do {
            let outcome = try await purchases.purchase(productID: productID)
            switch outcome {
            case .userCancelled:
                // Quiet path — no error, no state change.
                return
            case .success(let snapshot):
                applyOptimistic(snapshot)
            }
            await refreshFromServer()
        } catch {
            lastError = "Purchase failed: \(error.localizedDescription)"
        }
    }

    /// Restore previously-purchased entitlements (post-reinstall flow).
    /// RC returns the recovered snapshot; we apply it optimistically and
    /// then re-pull server-truth.
    func restorePurchases() async {
        do {
            let snapshot = try await purchases.restorePurchases()
            applyOptimistic(snapshot)
            await refreshFromServer()
        } catch {
            lastError = "Restore failed: \(error.localizedDescription)"
        }
    }

    /// Disassociate the current RC identity and cancel the customer-info
    /// stream. Called from `AppState.signOut()` so the next session starts
    /// anonymous until the next `bootstrap`.
    func teardown() async {
        streamTask?.cancel()
        streamTask = nil
        isStreamingCustomerInfo = false
        do {
            try await purchases.logOut()
        } catch {
            // Sign-out best-effort; log to lastError but proceed.
            lastError = "RevenueCat sign-out failed: \(error.localizedDescription)"
        }
        currentTier = .trial
        daysRemaining = nil
        inTrial = false
        enforcementEnabled = false
    }

    // MARK: - Reconciliation helpers

    /// Server-truth wins. Sets every field from `MeBillingResponse` so any
    /// prior optimistic state is overwritten on the next refresh.
    private func applyServerTruth(_ snapshot: MeBillingResponse) {
        currentTier = snapshot.tier
        daysRemaining = snapshot.daysRemaining
        inTrial = snapshot.inTrial
        enforcementEnabled = snapshot.enforcementEnabled
    }

    /// SDK-truth applied between `purchase` success and the next server
    /// refresh. Only upgrades the tier when the RC entitlement implies a
    /// higher one — never downgrades from server-truth.
    private func applyOptimistic(_ snapshot: RCCustomerInfoSnapshot) {
        let inferred = Self.inferredTier(from: snapshot)
        if shouldUpgrade(from: currentTier, to: inferred) {
            currentTier = inferred
            // RC has no notion of trial state — leave inTrial / daysRemaining
            // untouched until the next server refresh restores authoritative
            // values.
        }
    }

    /// Map RC active entitlement IDs to a `UserTier`. Ultimate beats pro;
    /// anything else implies the previously-known tier (so we don't
    /// downgrade in the brief reconciliation window).
    static func inferredTier(from snapshot: RCCustomerInfoSnapshot) -> UserTier {
        if snapshot.activeEntitlementIDs.contains(RCEntitlement.ultimate) {
            return .ultimate
        }
        if snapshot.activeEntitlementIDs.contains(RCEntitlement.pro) {
            return .pro
        }
        return .trial
    }

    /// Returns true when `candidate` is strictly higher than `current`
    /// along the tier ladder. Used to gate optimistic upgrades — server
    /// refresh is the only path that can move the tier downward.
    private func shouldUpgrade(from current: UserTier, to candidate: UserTier) -> Bool {
        Self.rank(candidate) > Self.rank(current)
    }

    /// HER-188 — true when `current` satisfies `required` along the tier
    /// ladder (`required` ≤ `current`). Exposed for `EntitlementGate` so
    /// the view modifier can decide pre-emptively whether to present the
    /// paywall without itself encoding the rank order.
    static func meets(_ current: UserTier, requires required: UserTier) -> Bool {
        rank(current) >= rank(required)
    }

    static func rank(_ tier: UserTier) -> Int {
        switch tier {
        case .archived: return -1
        case .lapsed:   return 0
        case .trial:    return 1
        case .pro:      return 2
        case .ultimate: return 3
        }
    }

    // MARK: - Customer-info stream

    private func startCustomerInfoStream() {
        streamTask?.cancel()
        let stream = purchases.customerInfoStream()
        isStreamingCustomerInfo = true
        streamTask = Task { [weak self] in
            for await snapshot in stream {
                guard let self else { return }
                await self.handleStreamEvent(snapshot)
            }
        }
    }

    private func handleStreamEvent(_ snapshot: RCCustomerInfoSnapshot) async {
        // RC pushes can outpace the webhook on cross-device upgrades, so
        // apply optimistically first to keep the UI responsive, then
        // converge against server-truth.
        applyOptimistic(snapshot)
        await refreshFromServer()
    }
}
