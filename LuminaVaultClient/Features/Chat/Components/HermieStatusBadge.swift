// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/HermieStatusBadge.swift
//
// Empty-state centerpiece for the AI chat: Hermie in a glass disc with
// a halo backdrop and a short status label ("Ready" / "Thinking…" /
// "Listening…"). Replaces the old full-screen splash so the initial
// view reads like a focused command center, not a launch screen.
import SwiftUI

struct HermieStatusBadge: View {
    @Environment(\.lvPalette) private var palette
    let mascotState: HermieMascotState
    let label: String
    var size: CGFloat = 96

    var body: some View {
        VStack(spacing: LVSpacing.md) {
            ZStack {
                LVHaloBackdrop(focalSize: size, intensity: LVGlow.hero, particleCount: 8)
                    .frame(width: size * 1.9, height: size * 1.9)
                    .allowsHitTesting(false)

                Circle()
                    .fill(palette.surface)
                    .frame(width: size, height: size)
                    .overlay {
                        Circle().stroke(
                            LinearGradient(
                                colors: [palette.glowPrimary, palette.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                    }
                    .shadow(color: palette.glowPrimary.opacity(0.5), radius: 20)

                HermieMascotView(state: mascotState, size: size * 1.05,
                                 fallbackImageName: "OnboardingMascot")
            }
            .frame(height: size * 1.4)

            Text(label)
                .lvFont(.microTag)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hermie — \(label)")
    }
}
