// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/ChatCosmicBackground.swift
//
// Shared backdrop for the AI chat surface. Used behind BOTH the empty
// "Input Hub" state and the active conversation so switching between
// them is seamless (same cosmic wash, same sparkle field). Black base +
// two palette-tinted radial glows + a drifting `SparkleField`.
import SwiftUI

struct ChatCosmicBackground: View {
    @Environment(\.lvPalette) private var palette

    var body: some View {
        ZStack {
            Color.black

            RadialGradient(
                colors: [palette.glowPrimary.opacity(0.12), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 500
            )

            RadialGradient(
                colors: [palette.accent.opacity(0.06), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 420
            )

            SparkleField(density: 18, maxRadius: 1.6)
                .opacity(0.4)
                .blendMode(.screen)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}
