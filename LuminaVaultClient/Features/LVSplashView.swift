// LuminaVaultClient/LuminaVaultClient/Features/LVSplashView.swift
import SwiftUI

struct LVSplashView: View {

    @Environment(\.lvPalette) private var palette

    @State private var pulseScale1: CGFloat = 0.5
    @State private var pulseScale2: CGFloat = 0.5
    @State private var pulseScale3: CGFloat = 0.5
    @State private var pulseOpacity1: Double = 0.5
    @State private var pulseOpacity2: Double = 0.5
    @State private var pulseOpacity3: Double = 0.5
    @State private var heroOpacity: Double = 0
    @State private var wordmarkOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var heroScale: CGFloat = 0.85

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.primary.opacity(0.18), lineWidth: 1.5)
                .scaleEffect(pulseScale1)
                .opacity(pulseOpacity1)
                .frame(width: 280, height: 280)
            Circle()
                .stroke(palette.primary.opacity(0.12), lineWidth: 1)
                .scaleEffect(pulseScale2)
                .opacity(pulseOpacity2)
                .frame(width: 280, height: 280)
            Circle()
                .stroke(palette.accent.opacity(0.10), lineWidth: 1)
                .scaleEffect(pulseScale3)
                .opacity(pulseOpacity3)
                .frame(width: 280, height: 280)

            VStack(spacing: LVSpacing.base) {
                SplashHeroRiveView(size: LVSize.mascotSmall)
                    .opacity(heroOpacity)
                    .scaleEffect(heroScale)

                Text("LUMINAVAULT")
                    .font(LVTypography.button.font)
                    .tracking(4.0)
                    .foregroundStyle(LinearGradient(
                        colors: [palette.accent, palette.primary],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .opacity(wordmarkOpacity)

                Text("Your memories, illuminated.")
                    .font(LVTypography.caption.font)
                    .foregroundStyle(palette.textSecondary)
                    .opacity(taglineOpacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .onAppear { startAnimations() }
    }

    private func startAnimations() {
        withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
            pulseScale1 = 2.2; pulseOpacity1 = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                pulseScale2 = 2.2; pulseOpacity2 = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                pulseScale3 = 2.2; pulseOpacity3 = 0
            }
        }
        withAnimation(.easeOut(duration: 0.7)) {
            heroOpacity = 1; heroScale = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeIn(duration: 0.5)) { wordmarkOpacity = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeIn(duration: 0.5)) { taglineOpacity = 1 }
        }
    }
}

#Preview {
    LVSplashView()
}
