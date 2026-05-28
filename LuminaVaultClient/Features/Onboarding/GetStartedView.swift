// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/GetStartedView.swift
import SwiftUI

struct GetStartedView: View {

    @Environment(\.lvPalette) private var palette

    var onContinue: () -> Void

    private let mascotSize: CGFloat = 300

    @State private var mascotOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var ctaOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.clear.lvBackground()

            LVHaloBackdrop(focalSize: mascotSize, intensity: LVGlow.hero)
                .allowsHitTesting(false)

            VStack(spacing: LVSpacing.xl) {
                Spacer(minLength: LVSpacing.xl)

                GetStartedHeroRiveView(size: mascotSize)
                    .lvPulse(active: true)
                    .opacity(mascotOpacity)

                VStack(spacing: LVSpacing.sm) {
                    Text("Welcome to LuminaVault")
                        .lvFont(.display)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [palette.accent, palette.primary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .multilineTextAlignment(.center)
                        .opacity(titleOpacity)

                    Text("Your memories, illuminated. Let Lumina remember everything for you — privately, on your own server.")
                        .lvFont(.body)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .opacity(subtitleOpacity)
                }
                .padding(.horizontal, LVSpacing.lg)
                .padding(.vertical, LVSpacing.lg)
                .lvGlassCard(cornerRadius: LVRadius.card, intensity: LVGlow.hero)
                .lvInnerGlow(cornerRadius: LVRadius.card, intensity: LVGlow.subtle)
                .padding(.horizontal, LVSpacing.xl)

                Spacer(minLength: LVSpacing.base)

                LVButton("Get Started") {
                    onContinue()
                }
                .padding(.horizontal, LVSpacing.xl)
                .padding(.bottom, LVSpacing.xl)
                .opacity(ctaOpacity)
                .shadow(color: palette.glowPrimary.opacity(LVGlow.subtle), radius: 28, y: 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { runIntro() }
    }

    private func runIntro() {
        withAnimation(.easeOut(duration: 0.6)) { mascotOpacity = 1 }
        withAnimation(.easeIn(duration: 0.5).delay(0.25)) { titleOpacity = 1 }
        withAnimation(.easeIn(duration: 0.5).delay(0.45)) { subtitleOpacity = 1 }
        withAnimation(.easeIn(duration: 0.5).delay(0.65)) { ctaOpacity = 1 }
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

