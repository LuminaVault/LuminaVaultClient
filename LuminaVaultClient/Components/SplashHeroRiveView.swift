// LuminaVaultClient/LuminaVaultClient/Components/SplashHeroRiveView.swift
import SwiftUI
import RiveRuntime

struct SplashHeroRiveView: View {

    @Environment(\.lvPalette) private var palette

    var size: CGFloat = 220
    var fallbackImageName: String = "SplashHero"
    var playsOnAppear: Bool = true

    @State private var viewModel: RiveViewModel?
    @State private var fallbackBreathing: CGFloat = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private static let riveFileName = "lumina_anims"
    private static let artboardName = "splash_hero"
    private static let stateMachineName = "State Machine 1"
    private static let isPlayingInput = "isPlaying"

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
        .onAppear {
            startFallbackBreathing()
            setLive(true)
        }
        .onDisappear { setLive(false) }
        .onChange(of: scenePhase) { _, phase in setLive(phase == .active) }
        .onChange(of: reduceMotion) { _, rm in setPlaying(playsOnAppear && !rm) }
    }

    func setPlaying(_ playing: Bool) {
        viewModel?.setInput(Self.isPlayingInput, value: playing)
    }

    private func loadIfAvailable() {
        guard viewModel == nil else { return }
        guard let vm = RiveAssets.viewModel(
            named: Self.riveFileName,
            artboardName: Self.artboardName,
            stateMachineName: Self.stateMachineName
        ) else { return }
        viewModel = vm
        vm.setInput(Self.isPlayingInput, value: playsOnAppear && !reduceMotion)
    }

    /// Pause the render loop offscreen/backgrounded — no idle CPU burn.
    private func setLive(_ live: Bool) {
        guard let viewModel else { return }
        if live && !reduceMotion {
            viewModel.play()
        } else {
            viewModel.pause()
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
