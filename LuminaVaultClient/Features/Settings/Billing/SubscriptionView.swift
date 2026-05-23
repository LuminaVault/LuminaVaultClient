// LuminaVaultClient/LuminaVaultClient/Features/Settings/Billing/SubscriptionView.swift
//
// HER-188 — Settings → Subscription pane. Renders current tier, trial
// state, and the Apple HIG-required actions:
//   - "Manage Subscription" via RC's hosted page (deep link to Settings.app)
//   - "Restore Purchases" (Apple HIG: must be reachable from any IAP flow)
//   - Terms of Service + Privacy Policy links
//
// The paywall itself is rendered by `PaywallView` via `.sheet(item:)`
// driven by `SubscriptionViewModel.presentedPaywallID`. Same component
// powers `EntitlementGate`, so visuals stay consistent.

import SwiftUI
import StoreKit
import LuminaVaultShared

struct SubscriptionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.lvPalette) private var palette
    @Environment(\.openURL) private var openURL
    @State private var viewModel: SubscriptionViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: appState.billingService === nil ? "none" : "live") {
            if viewModel == nil {
                viewModel = SubscriptionViewModel(billing: appState.billingService)
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: SubscriptionViewModel) -> some View {
        List {
            Section("Current plan") {
                tierBadgeRow(viewModel: viewModel)
                if viewModel.inTrial, let days = viewModel.daysRemaining {
                    trialCountdownRow(days: days)
                }
            }

            if viewModel.canUpgrade {
                Section {
                    Button {
                        viewModel.tapUpgrade()
                    } label: {
                        Label(upgradeCTA(currentTier: viewModel.currentTier), systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } footer: {
                    Text(upgradeFooter(currentTier: viewModel.currentTier))
                        .font(.caption)
                }
            }

            Section("Manage") {
                // HER-211 — StoreKit-native manage UI. Inline sheet
                // (no app-switch). Visible when the user has any
                // existing subscription history; surfaced unconditionally
                // here per Apple HIG §3.1.2 review checklist (the sheet
                // itself renders an "All subscriptions" empty state when
                // there's nothing to manage).
                Button {
                    viewModel.tapManageSubscription()
                } label: {
                    Label("Manage Subscription", systemImage: "creditcard.and.123")
                }
                .manageSubscriptionsSheet(isPresented: Binding(
                    get: { viewModel.isManageSubscriptionsPresented },
                    set: { viewModel.isManageSubscriptionsPresented = $0 }
                ))

                Button {
                    Task { await viewModel.restorePurchases() }
                } label: {
                    HStack {
                        Label("Restore Purchases", systemImage: "arrow.clockwise.circle")
                        Spacer()
                        if viewModel.isRestoreInFlight {
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isRestoreInFlight)
            }

            Section("Legal") {
                Link(destination: Config.termsOfServiceURL) {
                    Label("Terms of Service", systemImage: "doc.text")
                }
                Link(destination: Config.privacyPolicyURL) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
            }
        }
        .alert(
            "Restore failed",
            isPresented: Binding(
                get: { viewModel.restoreErrorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } }
            ),
            actions: { Button("OK", role: .cancel) { viewModel.dismissError() } },
            message: { Text(viewModel.restoreErrorMessage ?? "") }
        )
        .sheet(
            item: Binding(
                get: { viewModel.presentedPaywallID.map(PaywallSheetItem.init) },
                set: { item in
                    if item == nil { viewModel.dismissPaywall() }
                }
            )
        ) { item in
            PaywallView(paywallID: item.id)
                .environment(appState)
        }
    }

    // MARK: - Subviews

    private func tierBadgeRow(viewModel: SubscriptionViewModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tierIcon(viewModel.currentTier))
                .foregroundStyle(palette.glowPrimary)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.currentTier.rawValue.capitalized)
                    .font(.headline)
                Text(tierSubtitle(viewModel.currentTier))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func trialCountdownRow(days: Int) -> some View {
        HStack {
            Label("Trial", systemImage: "clock")
            Spacer()
            Text("\(days) day\(days == 1 ? "" : "s") left")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - Copy

    private func tierIcon(_ tier: UserTier) -> String {
        switch tier {
        case .trial:    return "sparkle"
        case .pro:      return "star.fill"
        case .ultimate: return "crown.fill"
        case .lapsed:   return "exclamationmark.triangle"
        case .archived: return "archivebox"
        }
    }

    private func tierSubtitle(_ tier: UserTier) -> String {
        switch tier {
        case .trial:    return "14-day free trial"
        case .pro:      return "All features unlocked"
        case .ultimate: return "All features + priority support"
        case .lapsed:   return "Subscription expired — renew to restore access"
        case .archived: return "Account archived"
        }
    }

    private func upgradeCTA(currentTier: UserTier) -> String {
        switch currentTier {
        case .pro: return "Upgrade to Ultimate"
        default:   return "Upgrade to Pro"
        }
    }

    private func upgradeFooter(currentTier: UserTier) -> String {
        switch currentTier {
        case .trial:    return "Try Pro free for 14 days. Cancel anytime."
        case .lapsed:   return "Restore full access by renewing your subscription."
        case .pro:      return "Unlock priority support and the Ultimate feature set."
        case .ultimate: return ""
        case .archived: return "Contact support to reactivate your account."
        }
    }
}

private struct PaywallSheetItem: Identifiable, Equatable {
    let id: String
}
