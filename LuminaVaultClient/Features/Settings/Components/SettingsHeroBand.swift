// LuminaVaultClient/LuminaVaultClient/Features/Settings/Components/SettingsHeroBand.swift
//
// HER-303 — hero band at the top of the Settings root: Lumina's head in a
// gold-rimmed disc beside the wordmark and tagline. (Memory Keeper, 2026-10,
// retired the drifting halo and gradient wordmark.)

import SwiftUI

struct SettingsHeroBand: View {
    @Environment(\.lvPalette) private var palette

    private let mascotSize: CGFloat = 80

    var body: some View {
        HStack(spacing: LVSpacing.base) {
            mascotDisc
            VStack(alignment: .leading, spacing: LVSpacing.xs) {
                Text("LuminaVault")
                    .lvFont(.title)
                    .foregroundStyle(palette.textPrimary)
                Text(BrandCopy.motto)
                    .lvFont(.callout)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, LVSpacing.lg)
        .padding(.horizontal, LVSpacing.base)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: LVRadius.card, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: LVRadius.card, style: .continuous)
                .fill(palette.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LVRadius.card, style: .continuous)
                .stroke(palette.glowPrimary.opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: LVRadius.card, style: .continuous))
        .lvInnerGlow(cornerRadius: LVRadius.card, intensity: LVGlow.subtle)
        .shadow(color: palette.glowPrimary.opacity(LVGlow.subtle), radius: 22)
    }

    private var mascotDisc: some View {
        ZStack {
            Circle().fill(palette.surfaceElevated)

            // Head crop in a disc with one gold hairline — the brand accent —
            // instead of the drifting halo, gradient ring and cyan bloom.
            HermieMascotView(state: .idle, size: mascotSize,
                             art: .head)
                .frame(width: mascotSize, height: mascotSize)
                .clipShape(Circle())
                .overlay {
                    Circle().strokeBorder(palette.accent.opacity(0.8), lineWidth: 1)
                }
        }
        .frame(width: mascotSize, height: mascotSize)
    }
}

#Preview("SettingsHeroBand · Dark") {
    SettingsHeroBand()
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .preferredColorScheme(.dark)
}

#Preview("SettingsHeroBand · Light") {
    SettingsHeroBand()
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .preferredColorScheme(.light)
}
