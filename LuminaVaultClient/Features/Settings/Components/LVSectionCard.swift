// LuminaVaultClient/LuminaVaultClient/Features/Settings/Components/LVSectionCard.swift
//
// HER-303 — reusable glass section card for Settings (and future
// surfaces). Replaces the inline `glassSection` helper in
// `SettingsRootView` and adds an `.lvInnerGlow` front-lit edge so
// cards feel illuminated from within, not just behind.

import SwiftUI

struct LVSectionCard<Content: View>: View {
    @Environment(\.lvPalette) private var palette

    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            Text(title.uppercased())
                .lvFont(.microTag)
                .foregroundStyle(palette.textSecondary)
                .tracking(2)
                .padding(.leading, LVSpacing.sm)

            VStack(spacing: 0) {
                content()
            }
            .lvGlassCard(cornerRadius: LVRadius.card, intensity: LVGlow.card)
            .lvInnerGlow(cornerRadius: LVRadius.card, intensity: LVGlow.subtle)
        }
    }
}

#Preview("LVSectionCard · Dark") {
    VStack(spacing: LVSpacing.xl) {
        LVSectionCard("Appearance") {
            Text("Theme picker placeholder")
                .padding()
        }
        LVSectionCard("Account & Data") {
            VStack(spacing: 0) {
                Text("Row 1").frame(maxWidth: .infinity).padding()
                Divider()
                Text("Row 2").frame(maxWidth: .infinity).padding()
            }
        }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .lvBackground()
    .preferredColorScheme(.dark)
}
