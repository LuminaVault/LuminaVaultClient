// LuminaVaultClient/LuminaVaultClient/Components/GetStartedHeroRiveView.swift
import SwiftUI
import RiveRuntime

struct GetStartedHeroRiveView: View {

    @Environment(\.lvPalette) private var palette

    var size: CGFloat = 240
    var fallbackImageName: String = "GetStartedHero"
    var fireWaveOnAppear: Bool = true

    @State private var viewModel: RiveViewModel?
    @State private var fallbackFloat: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let riveFileName = "get_started_hero"
    private static let stateMachineName = "State Machine 1"
    private static let waveInput = "wave"

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
                    .offset(y: fallbackFloat)
                    .shadow(color: palette.primary.opacity(0.40), radius: 32, y: 14)
                    .shadow(color: palette.accent.opacity(0.22), radius: 56, y: 22)
            }
        }
        .accessibilityLabel("Lumina the keeper of memories")
        .task { loadIfAvailable() }
        .onAppear { startFallbackFloat() }
    }

    func fireWave() {
        viewModel?.triggerInput(Self.waveInput)
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
        if fireWaveOnAppear {
            vm.triggerInput(Self.waveInput)
        }
    }

    private func startFallbackFloat() {
        guard viewModel == nil, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            fallbackFloat = -8
        }
    }
}

#Preview("Fallback PNG · Dark") {
    GetStartedHeroRiveView(size: 240)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .preferredColorScheme(.dark)
}
