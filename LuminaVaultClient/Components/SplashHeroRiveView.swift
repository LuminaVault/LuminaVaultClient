// LuminaVaultClient/LuminaVaultClient/Components/SplashHeroRiveView.swift
import SwiftUI
import RiveRuntime

struct SplashHeroRiveView: View {

    @Environment(\.lvPalette) private var palette

    var size: CGFloat = 220
    var fallbackImageName: String = "SplashHero"
    var firePulseOnAppear: Bool = true

    @State private var viewModel: RiveViewModel?
    @State private var fallbackBreathing: CGFloat = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let riveFileName = "splash_hero"
    private static let stateMachineName = "State Machine 1"
    private static let pulseInput = "pulse"

    var body: some View {
        Group {
            if let viewModel {
                viewModel.view()
                    .frame(width: size, height: size)
            } else {
                Image(fallbackImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .scaleEffect(fallbackBreathing)
                    .shadow(color: palette.primary.opacity(0.35), radius: 28, y: 8)
                    .shadow(color: palette.accent.opacity(0.18), radius: 44, y: 14)
            }
        }
        .accessibilityLabel("LuminaVault splash mark")
        .task { loadIfAvailable() }
        .onAppear { startFallbackBreathing() }
    }

    func firePulse() {
        viewModel?.triggerInput(Self.pulseInput)
    }

    private func loadIfAvailable() {
        guard viewModel == nil else { return }
        guard Bundle.main.url(forResource: Self.riveFileName, withExtension: "riv") != nil else {
            return
        }
        let vm = RiveViewModel(
            fileName: Self.riveFileName,
            stateMachineName: Self.stateMachineName
        )
        viewModel = vm
        if firePulseOnAppear {
            vm.triggerInput(Self.pulseInput)
        }
    }

    private func startFallbackBreathing() {
        guard viewModel == nil, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
            fallbackBreathing = 1.035
        }
    }
}

#Preview("Fallback PNG · Dark") {
    SplashHeroRiveView(size: 220)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .preferredColorScheme(.dark)
}
