// LuminaVaultClient/LuminaVaultClient/Utilities/Extensions/View+EntitlementGate.swift
//
// HER-188 — SwiftUI modifier that gates a view tree behind a `UserTier`.
//
// Two presentation paths converge on the same `PaywallView`:
//
//   1. **Pre-emptive** — when the view appears, `EntitlementGateModifier`
//      checks `BillingService.currentTier` against the required tier. If
//      the user is below, the paywall presents immediately so they never
//      see a screen they can't use.
//
//   2. **Reactive** — descendant call sites that hit a tier-gated API
//      endpoint catch `APIError.paymentRequired` and forward to the
//      `paywallPresenter` they read from the SwiftUI Environment. That
//      uses the server's `paywall_id` hint (when provided) which can A/B
//      different offerings without an app update.

import SwiftUI
import LuminaVaultShared

extension View {
    /// Gate this view behind a minimum subscription tier.
    ///
    /// - Parameters:
    ///   - tier: The minimum `UserTier` required. `BillingService.meets(_:requires:)`
    ///     decides whether the user qualifies; comparison uses the static rank
    ///     ladder defined alongside `BillingService.rank(_:)`.
    ///   - paywallID: RC offering identifier to present when the gate fires
    ///     pre-emptively. Server 402 responses override this with their own
    ///     `paywall_id` hint, so this only matters for the on-appear path.
    func requiresTier(_ tier: UserTier, paywallID: String = "default") -> some View {
        modifier(EntitlementGateModifier(requiredTier: tier, defaultPaywallID: paywallID))
    }
}

/// Forwarder used by descendant views that catch `APIError.paymentRequired`.
/// Reads via `@Environment(\.paywallPresenter)`. `nil` when the surrounding
/// tree has no `.requiresTier(_:)` modifier — call sites should fail closed
/// (surface a generic error toast) in that case rather than silently no-op.
struct PaywallPresenter: Sendable {
    /// Server-issued `paywall_id` hint (or `nil` to fall back to the modifier's
    /// `defaultPaywallID`). Called on the main actor.
    let present: @MainActor (String?) -> Void
}

private struct PaywallPresenterKey: EnvironmentKey {
    static let defaultValue: PaywallPresenter? = nil
}

extension EnvironmentValues {
    var paywallPresenter: PaywallPresenter? {
        get { self[PaywallPresenterKey.self] }
        set { self[PaywallPresenterKey.self] = newValue }
    }
}

/// Wrapping the paywall ID in `Identifiable` so `.sheet(item:)` can drive
/// the presentation off a single optional binding (SwiftUI requires the
/// item type to conform; `String` doesn't). Hoisted to internal in HER-211
/// so `AppState.pendingPaywallID` can publish the same type — root-level
/// universal paywall sheet binds against it directly.
struct PaywallPresentation: Identifiable, Equatable, Sendable {
    let id: String
}

private struct EntitlementGateModifier: ViewModifier {
    let requiredTier: UserTier
    let defaultPaywallID: String

    @Environment(AppState.self) private var appState
    @State private var presented: PaywallPresentation?

    func body(content: Content) -> some View {
        content
            .environment(\.paywallPresenter, makePresenter())
            .task(id: appState.billingService?.currentTier) {
                evaluatePreemptiveGate()
            }
            .sheet(item: $presented) { item in
                PaywallView(paywallID: item.id)
                    .environment(appState)
            }
    }

    private func makePresenter() -> PaywallPresenter {
        let fallback = defaultPaywallID
        return PaywallPresenter { serverHint in
            // Server's `paywall_id` wins when present; otherwise use the
            // modifier's default offering. Either way, the modal stays a
            // single shared `PaywallView` instance for the surrounding
            // subtree — avoids double sheets when multiple descendants
            // throw `.paymentRequired` near-simultaneously.
            presented = PaywallPresentation(id: serverHint ?? fallback)
        }
    }

    private func evaluatePreemptiveGate() {
        // No BillingService -> user is signed out (cold launch path). The
        // gate's parent is responsible for routing unauthenticated users
        // somewhere else; don't present a paywall over an empty session.
        guard let billing = appState.billingService else { return }

        // Trial users can already use most surfaces; only present when the
        // strict comparison fails. `.archived` / `.lapsed` users always
        // see the paywall here regardless of tier.
        if BillingService.meets(billing.currentTier, requires: requiredTier) {
            return
        }
        if presented == nil {
            presented = PaywallPresentation(id: defaultPaywallID)
        }
    }
}
