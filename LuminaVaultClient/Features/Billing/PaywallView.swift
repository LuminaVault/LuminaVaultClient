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

    /// Why we can or can't show plans. See `PaywallOfferingState` — the three
    /// failure causes are deliberately distinct, because only one of them is
    /// worth offering a retry for and only one of them is a real problem.
    @State private var offering: PaywallOfferingState = .checking

    /// Injected so the three failure causes can be asserted in tests, and so a
    /// preview doesn't emit events.
    private let telemetry: any TelemetryProtocol

    init(paywallID: String? = nil, telemetry: any TelemetryProtocol = LoggerTelemetry()) {
        self.paywallID = paywallID
        self.telemetry = telemetry
    }

    var body: some View {
        ZStack(alignment: .top) {
            palette.surface.ignoresSafeArea()
            VStack(spacing: 0) {
                // `LVEmptyState` draws its own, larger mascot inside a
                // particle ring, so the chrome mascot is suppressed whenever a
                // failure state renders — two mascots stacked reads worse than
                // the blank screen this replaces.
                if offering.showsStorePaywall || offering == .checking {
                    HermieMascotView(state: mascotState, size: 120)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                        .padding(.bottom, 8)
                }
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
                switch offering {
                case .checking:
                    offeringLoading
                case .notConfigured:
                    storeUnavailable
                case .fetchFailed(let reason):
                    fetchFailed(reason)
                case .empty:
                    noPlansPublished
                case .available:
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
                }
            }
        }
        .presentationDragIndicator(.visible)
        .task { await resolveOffering() }
    }

    // MARK: - Failure states

    /// The expected state on TestFlight: `Config.Beta.xcconfig` ships an empty
    /// `LV_RC_API_KEY` on purpose, so `Purchases.configure` never runs. Nothing
    /// is broken and nothing needs fixing in the RevenueCat dashboard — say so
    /// plainly rather than implying a network problem.
    private var storeUnavailable: some View {
        LVEmptyState(
            headline: "Purchases aren't available in this build",
            supporting: "This build ships without a store key, so nothing can be bought here. "
                + "Your plan, and everything you've already unlocked, are unaffected.",
            primaryCTA: ("Got it", { dismiss() })
        )
    }

    /// The only transient cause, and so the only one with a retry. Its absence
    /// was the single biggest defect in the old screen: a user with a flaky
    /// connection had no way forward but to close the sheet.
    private func fetchFailed(_ reason: String) -> some View {
        LVEmptyState(
            headline: "Couldn't load plans",
            supporting: reason,
            primaryCTA: ("Try again", {
                offering = .checking
                Task { await resolveOffering() }
            })
        )
    }

    /// Configured, reachable, and still nothing to sell — an offering with no
    /// packages, or none matching the server's `paywall_id`. Fixable only in
    /// the RevenueCat dashboard, so pointedly *not* offering a retry.
    private var noPlansPublished: some View {
        LVEmptyState(
            headline: "No plans available right now",
            supporting: "Plans aren't published for this build yet. Please try again shortly.",
            primaryCTA: ("Close", { dismiss() })
        )
    }

    /// Never leaves the sheet blank while the offering fetch is in flight.
    private var offeringLoading: some View {
        VStack(spacing: LVSpacing.base) {
            ProgressView()
                .tint(palette.glowPrimary)
            Text("Loading plans…")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(LVSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Classifies the fetch into one of the four terminal states. The error is
    /// carried into `.fetchFailed` rather than swallowed, and every non-success
    /// outcome is reported once — without that, the three causes are
    /// indistinguishable in production, which is how a blank sheet went
    /// unexplained.
    private func resolveOffering() async {
        guard Purchases.isConfigured else {
            offering = PaywallOfferingResolver.state(
                isConfigured: false, fetchFailure: nil, availablePackageCount: nil
            )
            report(offering)
            return
        }
        do {
            let offerings = try await Purchases.shared.offerings()
            let current = offerings.current ?? offerings.all[paywallID ?? ""]
            offering = PaywallOfferingResolver.state(
                isConfigured: true,
                fetchFailure: nil,
                availablePackageCount: current?.availablePackages.count
            )
        } catch {
            offering = PaywallOfferingResolver.state(
                isConfigured: true,
                fetchFailure: error.localizedDescription,
                availablePackageCount: nil
            )
        }
        report(offering)
    }

    private func report(_ state: PaywallOfferingState) {
        guard let reason = state.telemetryReason else { return }
        telemetry.track(
            "paywall_unavailable",
            properties: ["reason": reason, "paywallId": paywallID ?? "default"]
        )
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

}
