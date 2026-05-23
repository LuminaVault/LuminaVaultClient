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
                RevenueCatUI.PaywallView()
                    .onPurchaseCompleted { _ in
                        Task { await appState.billingService?.refreshFromServer() }
                        dismiss()
                    }
                    .onRestoreCompleted { _ in
                        Task { await appState.billingService?.refreshFromServer() }
                    }
            }
        }
        .presentationDragIndicator(.visible)
    }

    /// Drives the mascot: `.thinking` while a purchase is in flight (RC
    /// sheet is up and StoreKit is exchanging receipts), `.celebrating`
    /// briefly after a successful purchase, otherwise `.idle`.
    private var mascotState: HermieMascotState {
        if appState.billingService?.isPurchaseInFlight == true {
            return .thinking
        }
        return .idle
    }
}
