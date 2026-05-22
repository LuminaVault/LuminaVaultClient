// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/DashboardCardShell.swift
//
// HER-244 — reusable card chrome for the OS Shell Home/Dashboard. Mirrors
// the established SpaceCardView pattern (palette.backgroundBase fill + palette.primary stroke +
// 16-pt corner radius) so cards land in the same visual family as the
// rest of the app.

import SwiftUI

struct DashboardCardShell<Content: View>: View {

    @Environment(\.lvPalette) private var palette

    let title: String
    let icon: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.primary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lvGlassCard(cornerRadius: 16, intensity: 0.45)
    }
}
