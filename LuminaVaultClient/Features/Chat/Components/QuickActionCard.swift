// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/QuickActionCard.swift
//
// Pinned quick-action cards for the empty AI state. A horizontal
// carousel of glass cards built from the server's `/v1/me/suggestions`
// payload; tapping one seeds the composer and sends. Replaces the old
// full-width suggestion buttons that overlapped the composer and ate
// its taps.
import SwiftUI

struct QuickActionCard: View {
    @Environment(\.lvPalette) private var palette
    let icon: LVIcon
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: LVSpacing.sm) {
                LVIconView(icon, size: 22, tint: palette.glowPrimary)
                    .shadow(color: palette.glowPrimary.opacity(0.5), radius: 6)

                Text(title)
                    .lvFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .frame(width: 150, height: 110, alignment: .topLeading)
            .padding(LVSpacing.base)
            .lvGlassCard(cornerRadius: LVRadius.lg, intensity: LVGlow.card)
            .lvGlowStroke(cornerRadius: LVRadius.lg, intensity: LVGlow.subtle)
        }
        .buttonStyle(.plain)
        .lvGlowPress()
    }
}

/// Horizontally-scrolling row of `QuickActionCard`s. Lives well above
/// the composer so it can never overlap or intercept its taps.
struct QuickActionsCarousel: View {
    let suggestions: [String]
    let onTap: (String) -> Void

    /// Icon rotation so the cards feel varied without per-suggestion
    /// metadata from the server.
    private static let icons: [LVIcon] = [
        .sparkles, .brainHeadProfile, .lightbulbFill, .docText, .chartUp,
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LVSpacing.md) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                    QuickActionCard(
                        icon: Self.icons[index % Self.icons.count],
                        title: suggestion,
                        action: { onTap(suggestion) }
                    )
                }
            }
            .padding(.horizontal, LVSpacing.lg)
        }
    }
}
