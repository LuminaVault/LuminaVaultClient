// LuminaVaultClient/LuminaVaultClient/Features/LVSplashView.swift
import SwiftUI

/// The first SwiftUI frame after launch.
///
/// Memory Keeper (2026-10): this picks up exactly where the static launch
/// screen (Info.plist `UILaunchScreen` → `LaunchBackground` + `LaunchMark`)
/// leaves off — same colour, same mark, same size, same centre — so there is
/// no flash or jump. Only the wordmark and tagline arrive, below the mark.
/// The repeating pulse rings are gone; nothing here loops.
struct LVSplashView: View {

    @Environment(\.lvPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var wordmarkOpacity: Double = 0
    @State private var taglineOpacity: Double = 0

    /// Matches the launch image's 1x width so the hand-off is pixel-stable.
    private let markWidth: CGFloat = 120

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()

            Image("LaunchMark")
                .resizable()
                .scaledToFit()
                .frame(width: markWidth)
                .accessibilityHidden(true)
                // Overlay, not a VStack: the mark must stay dead-centre where
                // the launch screen put it while the text appears below.
                .overlay(alignment: .top) {
                    VStack(spacing: LVSpacing.sm) {
                        Image("Wordmark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220)
                            .opacity(wordmarkOpacity)
                        Text("Your memories, illuminated.")
                            .font(LVTypography.footnote.font)
                            .foregroundStyle(palette.textSecondary)
                            .opacity(taglineOpacity)
                    }
                    .fixedSize()
                    .offset(y: markWidth + LVSpacing.lg)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("LuminaVault. Your memories, illuminated.")
        .onAppear(perform: reveal)
    }

    private func reveal() {
        guard !reduceMotion else {
            wordmarkOpacity = 1; taglineOpacity = 1
            return
        }
        withAnimation(.easeOut(duration: 0.35).delay(0.15)) { wordmarkOpacity = 1 }
        withAnimation(.easeOut(duration: 0.35).delay(0.35)) { taglineOpacity = 1 }
    }
}

#Preview("Dark") {
    LVSplashView().preferredColorScheme(.dark)
}

#Preview("Light") {
    LVSplashView().preferredColorScheme(.light)
}
