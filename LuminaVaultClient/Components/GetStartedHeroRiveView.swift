// LuminaVaultClient/LuminaVaultClient/Components/GetStartedHeroRiveView.swift
import SwiftUI
import RiveRuntime

struct GetStartedHeroRiveView: View {

    @Environment(\.lvPalette) private var palette

    var size: CGFloat = 240
    var fallbackImageName: String = "GetStartedHero"
    var playsOnAppear: Bool = true

    @State private var viewModel: RiveViewModel?
    @State private var fallbackFloat: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private static let riveFileName = "get_started_hero"
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
                    .offset(y: fallbackFloat)
                    .shadow(color: palette.primary.opacity(0.40), radius: 32, y: 14)
                    .shadow(color: palette.accent.opacity(0.22), radius: 56, y: 22)
            }
        }
        .accessibilityLabel("Lumina the keeper of memories")
        .task { loadIfAvailable() }
        .onAppear {
            startFallbackFloat()
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
