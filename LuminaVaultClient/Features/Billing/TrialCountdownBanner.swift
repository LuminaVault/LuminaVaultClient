// LuminaVaultClient/LuminaVaultClient/Features/Billing/TrialCountdownBanner.swift
//
// HER-211 — compact banner shown on Today + Settings root when the user is
// in trial and within `Self.urgencyThreshold` days of expiry. Render-only;
// reads directly off `AppState.billingService`. Tapping the banner sets
// `appState.pendingPaywallID` so the root-level paywall sheet
// (`LuminaVaultClientApp`) handles presentation — same path the universal
// 402 interceptor uses, so all paywall entry points converge on a single
// sheet binding.

import SwiftUI
import LuminaVaultShared

struct TrialCountdownBanner: View {
    /// Banner appears when remaining trial days drop strictly below this
    /// threshold. Per HER-211 spec: "tier == trial and < 5 days remaining".
    static let urgencyThreshold = 5

    @Environment(AppState.self) private var appState
    @Environment(\.lvPalette) private var palette

    var body: some View {
        if shouldShow {
            Button {
                tapUpgrade()
            } label: {
                bannerContent
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Opens the upgrade paywall")
        }
    }

    // MARK: - Visibility

    /// True iff there's a live `BillingService`, tier is `.trial`,
    /// `daysRemaining` is non-nil, and it falls under the threshold.
    /// Exposed as `internal` for `TrialCountdownBannerVisibilityTests`.
    static func shouldShow(billing: BillingService?) -> Bool {
        guard let billing,
              billing.inTrial,
              billing.currentTier == .trial,
              let days = billing.daysRemaining,
              days < urgencyThreshold else {
            return false
        }
        return true
    }

    private var shouldShow: Bool {
        Self.shouldShow(billing: appState.billingService)
    }

    // MARK: - Content

    private var bannerContent: some View {
        HStack(spacing: 12) {
            LVIconView(.clockBadgeExclamationmark, size: 20, tint: palette.glowPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Upgrade to keep full access.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            LVIconView(.chevronRight, size: 13, tint: .secondary, weight: .semibold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.glowPrimary.opacity(0.4), lineWidth: 1)
        )
    }

    private var headline: String {
        let days = appState.billingService?.daysRemaining ?? 0
        switch days {
        case 0:  return "Trial ends today"
        case 1:  return "Trial ends tomorrow"
        default: return "Trial: \(days) days left"
        }
    }

    private var accessibilityLabel: String {
        "\(headline). Tap to upgrade."
    }

    // MARK: - Action

    private func tapUpgrade() {
        appState.pendingPaywallID = PaywallPresentation(id: "default")
    }
}
