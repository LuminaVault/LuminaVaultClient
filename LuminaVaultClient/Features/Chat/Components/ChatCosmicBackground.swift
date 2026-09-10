// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/ChatCosmicBackground.swift
//
// Shared backdrop for the AI chat surface. Used behind BOTH the empty
// "Input Hub" state and the active conversation so switching between
// them is seamless (same wash, same sparkle field).
//
// Dark: black base + two palette-tinted radial glows + a drifting
// `SparkleField` (unchanged, and pinned by the `think-empty-dark` snapshot).
// Light: the palette's base and nothing else. The base used to be `Color.black`
// in both schemes, so a light-mode user saw a black starfield under a light
// header and tab bar — it read as the whole app flipping theme. The layer
// decision is factored into `Layers` so it can be asserted without rendering.
import SwiftUI

struct ChatCosmicBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.lvPalette) private var palette

    /// What the backdrop draws for a given scheme + palette. Like
    /// `View+LVBackground`, the starfield only exists in the dark. Dark keeps
    /// its black base because the CI snapshot baseline is recorded on a
    /// runtime (iOS 26.4) that an Xcode 26.2 machine cannot re-record;
    /// moving it to `palette.backgroundBase` is a one-line change once the
    /// baseline can be re-recorded there.
    struct Layers: Equatable {
        let base: Color
        let showsSparkles: Bool

        init(scheme: ColorScheme, palette: LVPalette) {
            let isDark = scheme == .dark
            base = isDark ? .black : palette.backgroundBase
            showsSparkles = isDark
        }
    }

    var body: some View {
        let layers = Layers(scheme: scheme, palette: palette)
        ZStack {
            layers.base

            if layers.showsSparkles {
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

                // `.screen` lightens what is underneath; on a light base that
                // is invisible noise, so the whole layer is dark-only.
                SparkleField(density: 8, maxRadius: 1.6, activeWhenTab: "think")
                    .opacity(0.4)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}
