// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/GetStartedView.swift
import SwiftUI

struct GetStartedView: View {

    @Environment(\.lvPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var onContinue: () -> Void

    /// Offset-based intro — content stays fully opaque so a stalled animation
    /// on device never leaves an empty screen.
    @State private var introOffset: CGFloat = 0

    // Memory Keeper (2026-10): the key art is the hero, framed as a card. The
    // halo backdrop (which was wider than the screen and pushed the whole
    // stack — title, copy and CTA — past both edges), pulse, glass card and
    // gradient headline are gone; the serif title echoes the wordmark.
    var body: some View {
        GeometryReader { proxy in
            let heroWidth = proxy.size.width - LVSpacing.xl * 2

            VStack(spacing: LVSpacing.xl) {
                Spacer(minLength: LVSpacing.lg)

                GetStartedHeroRiveView(size: heroWidth)
                    .clipShape(RoundedRectangle(cornerRadius: LVRadius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: LVRadius.card, style: .continuous)
                            .strokeBorder(palette.surfaceStroke, lineWidth: 1)
                    }

                VStack(spacing: LVSpacing.md) {
                    Text("Your Knowledge, Transcended")
                        .lvFont(.brandDisplay)
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Your memories, illuminated. Let Lumina remember everything for you — privately, on your own server.")
                        .lvFont(.body)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, LVSpacing.xl)

                Spacer(minLength: LVSpacing.base)

                LVButton("Begin Journey") {
                    onContinue()
                }
                .padding(.horizontal, LVSpacing.xl)
                .padding(.bottom, LVSpacing.xl)
            }
            .frame(width: proxy.size.width)
            .offset(y: introOffset)
        }
        .lvBackground()
        .animation(nil, value: introOffset)
        .onAppear { runIntro() }
    }

    private func runIntro() {
        guard !reduceMotion else { return }
        introOffset = 24
        withAnimation(.easeOut(duration: 0.6)) { introOffset = 0 }
    }
}

#Preview("Get Started · Dark") {
    GetStartedView(onContinue: {})
        .preferredColorScheme(.dark)
}

#Preview("Get Started · Light") {
    GetStartedView(onContinue: {})
        .preferredColorScheme(.light)
}