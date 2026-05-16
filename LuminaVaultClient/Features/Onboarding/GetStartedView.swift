// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/GetStartedView.swift
import SwiftUI

struct GetStartedView: View {
    var onContinue: () -> Void

    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var ctaOpacity: Double = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)

            GetStartedHeroRiveView(size: 260)

            VStack(spacing: 10) {
                Text("Welcome to LuminaVault")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(LinearGradient(
                        colors: [.lvAmber, .lvCyan],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .multilineTextAlignment(.center)
                    .opacity(titleOpacity)

                Text("Your memories, illuminated. Let Lumina remember everything for you — privately, on your own server.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.lvTextSub)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(subtitleOpacity)
            }

            Spacer(minLength: 16)

            LVButton("Get Started") {
                onContinue()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .opacity(ctaOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .onAppear { runIntro() }
    }

    private func runIntro() {
        withAnimation(.easeIn(duration: 0.5).delay(0.15)) { titleOpacity = 1 }
        withAnimation(.easeIn(duration: 0.5).delay(0.35)) { subtitleOpacity = 1 }
        withAnimation(.easeIn(duration: 0.5).delay(0.55)) { ctaOpacity = 1 }
    }
}

#Preview("Get Started · Dark") {
    GetStartedView(onContinue: {})
        .preferredColorScheme(.dark)
}
