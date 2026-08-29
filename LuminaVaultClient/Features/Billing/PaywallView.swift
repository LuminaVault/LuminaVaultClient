// LuminaVaultClient/LuminaVaultClient/Features/Billing/PaywallView.swift
//
// HER-188 — themed wrapper around RevenueCatUI's production `PaywallView`.
//
// RC ships a SwiftUI paywall component that handles offering fetch, intro
// offer copy localization, Apple HIG-compliant Restore Purchases button,
// and the StoreKit purchase sheet. We wrap it in our visual chrome —
// Hermie mascot on top, sci-fi palette behind — so the paywall looks like
// part of LuminaVault rather than RC's default template.
//
// The two RC callbacks (`onPurchaseCompleted`, `onRestoreCompleted`) force
// `BillingService.refreshFromServer()` so server-truth (the webhook-driven
// `MeBillingResponse`) wins on the next UI render. Without these, the UI
// would briefly read the optimistic RC tier and then snap to server-truth
// — these callbacks make the convergence explicit.

import SwiftUI
import StoreKit
import RevenueCat
import RevenueCatUI

struct PaywallView: View {
    /// RC offering identifier. `nil` falls back to RC's `current` offering
    /// (the one tagged `default` in the dashboard). Server's `paywall_id`
    /// hint flows here verbatim.
    let paywallID: String?

    @Environment(AppState.self) private var appState
    @Environment(\.lvPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    /// HER-298 — SwiftUI wrapper around `SKStoreReviewController`. Apple
    /// silently throttles past 3 prompts per device per 365 days, so we
    /// can fire it on every successful purchase without local tracking.
    @Environment(\.requestReview) private var requestReview

    /// HER-297 — latched on a successful purchase so the mascot plays its
    /// `.celebrating` Rive trigger while the sheet unwinds. Owned by the
    /// view, so it dies with the sheet and the mascot reverts to `.idle`
    /// on the next presentation. Never set on cancel/restore, so cancelled
    /// purchases don't celebrate.
    @State private var celebrating = false

    init(paywallID: String? = nil) {
        self.paywallID = paywallID
    }

    var body: some View {
        ZStack(alignment: .top) {
            palette.surface.ignoresSafeArea()
            VStack(spacing: 0) {
                HermieMascotView(state: mascotState, size: 120)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 8)
                // RevenueCatUI's `PaywallView` hard-crashes in release builds when
                // the SDK is unusable. An unconfigured `Purchases` takes RevenueCatUI
                // `PaywallView.swift:308`; a failed offering fetch takes `:265`. Both
                // build RC's `DebugErrorView` with `releaseBehavior: .fatalError`, and
                // that branch is a literal `fatalError()` under `#else` — so Debug
                // renders an error view and only TestFlight/App Store builds die
                // (EXC_BREAKPOINT).
                //
                // `AppState.onPaymentRequired` presents this sheet from the app root on
                // any 402, so a single paid endpoint could take the whole app down.
                // Gate on the same signal `PurchasesProxyFactory` already trusts.
                if Purchases.isConfigured {
                    RevenueCatUI.PaywallView()
                        .onPurchaseCompleted { _ in
                            // HER-211 — fire-and-forget server refresh so the
                            // UI converges off the webhook-driven tier.
                            // HER-298 — ~2 s delay lets the RC checkout sheet
                            // unwind + the celebration mascot (HER-297) land,
                            // then surface the review prompt at the moment
                            // the user's just paid (highest 5-star yield).
                            // HER-297 — celebrate immediately so the mascot
                            // animates through the ~2 s unwind window before
                            // the sheet dismisses.
                            celebrating = true
                            Task { @MainActor in
                                await appState.billingService?.refreshFromServer()
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                requestReview()
                                dismiss()
                            }
                        }
                        .onRestoreCompleted { _ in
                            Task { await appState.billingService?.refreshFromServer() }
                        }
                } else {
                    billingUnavailable
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    /// Drives the mascot: `.thinking` while a purchase is in flight (RC
    /// sheet is up and StoreKit is exchanging receipts), `.celebrating`
    /// briefly after a successful purchase, otherwise `.idle`.
    private var mascotState: HermieMascotState {
        if celebrating {
            return .celebrating
        }
        if appState.billingService?.isPurchaseInFlight == true {
            return .thinking
        }
        return .idle
    }

    /// Shown instead of RC's paywall when the SDK never configured — a
    /// missing or placeholder `LV_RC_API_KEY`. Entitlements still come from
    /// server-truth via `/v1/auth/me/billing`; the only thing unavailable is
    /// starting a purchase from this build.
    private var billingUnavailable: some View {
        VStack(spacing: LVSpacing.base) {
            Text("Subscriptions unavailable")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            Text("This build can't reach the store. Your existing plan is unaffected.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.glowPrimary)
                .padding(.top, LVSpacing.sm)
        }
        .padding(LVSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}
