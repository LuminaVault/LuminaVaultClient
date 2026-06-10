// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/GetStartedView.swift
import SwiftUI

struct GetStartedView: View {

    @Environment(\.lvPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var onContinue: () -> Void

    private let mascotSize: CGFloat = 300

    /// Offset-based intro — content stays fully opaque so a stalled animation
    /// on device never leaves an empty screen with only glass-card chrome.
    @State private var introOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.clear.lvBackground()

            LVHaloBackdrop(focalSize: mascotSize, intensity: LVGlow.hero)
                .allowsHitTesting(false)

            VStack(spacing: LVSpacing.xl) {
                Spacer(minLength: LVSpacing.xl)

                GetStartedHeroRiveView(size: mascotSize)
                    .lvPulse(active: true)

                VStack(spacing: LVSpacing.sm) {
                    Text("Your Knowledge, Transcended")
                        .lvFont(.display)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [palette.accent, palette.primary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .multilineTextAlignment(.center)

                    Text("Your memories, illuminated. Let Lumina remember everything for you — privately, on your own server.")
                        .lvFont(.body)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, LVSpacing.lg)
                .padding(.vertical, LVSpacing.lg)
                .lvGlassCard(cornerRadius: LVRadius.card, intensity: LVGlow.hero)
                .lvInnerGlow(cornerRadius: LVRadius.card, intensity: LVGlow.subtle)
                .padding(.horizontal, LVSpacing.xl)

                Spacer(minLength: LVSpacing.base)

                LVButton("Begin Journey") {
                    onContinue()
                }
                .padding(.horizontal, LVSpacing.xl)
                .padding(.bottom, LVSpacing.xl)
                .shadow(color: palette.glowPrimary.opacity(LVGlow.subtle), radius: 28, y: 12)
            }
            .offset(y: introOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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