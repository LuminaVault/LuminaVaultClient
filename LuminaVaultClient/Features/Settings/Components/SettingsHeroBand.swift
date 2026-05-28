// LuminaVaultClient/LuminaVaultClient/Features/Settings/Components/SettingsHeroBand.swift
//
// HER-303 — cinematic hero band at the top of the Settings root.
// Composes `LVHaloBackdrop` (drifting cyan/secondary halo + dust)
// behind the mascot disc, plus a gradient wordmark + tagline.

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
                    .foregroundStyle(
                        LinearGradient(
                            colors: [palette.glowPrimary, palette.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text("Your second brain.")
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
            LVHaloBackdrop(focalSize: mascotSize, intensity: LVGlow.focused, particleCount: 8)
                .frame(width: mascotSize * 2.2, height: mascotSize * 2.2)
                .allowsHitTesting(false)

            HermieMascotView(state: .idle, size: mascotSize,
                             fallbackImageName: "hermie-hero")
                .frame(width: mascotSize, height: mascotSize)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    palette.glowPrimary.opacity(0.8),
                                    palette.accent.opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.4
                        )
                }
                .shadow(color: palette.glowPrimary.opacity(0.65), radius: 14)
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
