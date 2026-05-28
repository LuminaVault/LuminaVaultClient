// LuminaVaultClient/LuminaVaultClient/Features/Capture/Components/CaptureCard.swift
//
// HER-305 — shared glass-card wrapper used by every section in the
// Capture sheet's mode bodies. Optional eyebrow row (icon + title)
// + internal padding + the standard `.lvGlassCard` look.

import SwiftUI

struct CaptureCard<Content: View>: View {
    @Environment(\.lvPalette) private var palette

    let eyebrowIcon: LVIcon?
    let eyebrowTitle: String?
    let footer: String?
    let content: Content

    init(
        eyebrowIcon: LVIcon? = nil,
        eyebrowTitle: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrowIcon = eyebrowIcon
        self.eyebrowTitle = eyebrowTitle
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            if eyebrowIcon != nil || eyebrowTitle != nil {
                HStack(spacing: LVSpacing.sm) {
                    if let icon = eyebrowIcon {
                        LVIconView(icon, size: 14, tint: palette.glowPrimary)
                    }
                    if let title = eyebrowTitle {
                        Text(title)
                            .lvFont(.microTag)
                            .foregroundStyle(palette.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.6)
                    }
                }
            }
            content
                .frame(maxWidth: .infinity, alignment: .leading)

            if let footer {
                Text(footer)
                    .lvFont(.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(LVSpacing.base)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: 0.55)
    }
}

#Preview {
    ZStack {
        Color(LVPalette.cyanGoldDark.backgroundBase).ignoresSafeArea()
        VStack(spacing: LVSpacing.lg) {
            CaptureCard(eyebrowIcon: .docText, eyebrowTitle: "Memory",
                        footer: "Plain text, saved straight to your vault.") {
                Text("What's on your mind?")
                    .foregroundStyle(.white.opacity(0.6))
            }
            CaptureCard(eyebrowIcon: .linkCircle, eyebrowTitle: "Link") {
                Text("https://example.com/article")
                    .lvFont(.mono)
                    .foregroundStyle(.white)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
