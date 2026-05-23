// LuminaVaultClient/LuminaVaultClient/Features/Settings/Billing/SubscriptionViewModel.swift
//
// HER-188 — view model for the Settings → Subscription pane. Reads from
// `BillingService` (server-truth) and exposes the small set of derived
// fields the SwiftUI view binds to. Restore + Upgrade actions delegate
// to `BillingService` so RC stays behind the proxy seam.

import Foundation
import LuminaVaultShared

@MainActor
@Observable
final class SubscriptionViewModel {
    /// `nil` when the user is signed out or RC config is missing —
    /// the view falls back to an "unavailable" state without crashing.
    let billing: BillingService?

    /// Bound by the view: tapping "Upgrade" sets this to the offering ID
    /// the paywall sheet should present. `nil` keeps the sheet dismissed.
    var presentedPaywallID: String?

    /// HER-211 — bound to `.manageSubscriptionsSheet`. SwiftUI flips this
    /// back to false on dismiss; the view model only ever sets it true
    /// from `tapManageSubscription()`. Source of truth for whether the
    /// StoreKit-native manage UI is visible.
    var isManageSubscriptionsPresented: Bool = false

    /// Set when `restorePurchases()` raises an error so the view can
    /// surface a banner. Cleared by `dismissError()`.
    private(set) var restoreErrorMessage: String?

    init(billing: BillingService?) {
        self.billing = billing
    }

    var currentTier: UserTier {
        billing?.currentTier ?? .trial
    }

    var inTrial: Bool {
        billing?.inTrial ?? false
    }

    var daysRemaining: Int? {
        billing?.daysRemaining
    }

    /// True when the "Upgrade" CTA should be visible. Pro users on the
    /// paid tier already have access; ultimate users have no upsell.
    var canUpgrade: Bool {
        switch currentTier {
        case .trial, .lapsed, .archived: return true
        case .pro:                       return true   // upsell to ultimate
        case .ultimate:                  return false
        }
    }

    /// Disabled while a restore is in flight to avoid double-tap into
    /// the StoreKit refresh.
    var isRestoreInFlight: Bool {
        billing?.isPurchaseInFlight ?? false
    }

    func tapUpgrade() {
        presentedPaywallID = "default"
    }

    /// HER-211 — surfaces the StoreKit-native manage UI.
    /// `.manageSubscriptionsSheet` modifier reads `isManageSubscriptionsPresented`.
    func tapManageSubscription() {
        isManageSubscriptionsPresented = true
    }

    func dismissPaywall() {
        // Refresh once on dismissal so a successful purchase landed via the
        // RC sheet flows through to the displayed tier even if the sheet
        // dismissed before `onPurchaseCompleted` fired.
        presentedPaywallID = nil
        Task { await billing?.refreshFromServer() }
    }

    func restorePurchases() async {
        guard let billing else {
            restoreErrorMessage = "Subscriptions are unavailable on this device."
            return
        }
        await billing.restorePurchases()
        if let err = billing.lastError {
            restoreErrorMessage = err
        }
    }

    func dismissError() {
        restoreErrorMessage = nil
    }
}
