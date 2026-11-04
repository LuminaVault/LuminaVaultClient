// LuminaVaultClient/LuminaVaultClient/Components/WingedScrollRiveView.swift
import SwiftUI
import RiveRuntime

struct WingedScrollRiveView: View {
    var size: CGFloat = 220
    var fallbackImageName: String = "WingedScroll"
    var playsOnAppear: Bool = true

    @State private var viewModel: RiveViewModel?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private static let riveFileName = "lumina_anims"
    private static let artboardName = "winged_scroll"
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
            }
        }
        .accessibilityLabel("LuminaVault")
        .task { loadIfAvailable() }
        .onAppear { setLive(true) }
        .onDisappear { setLive(false) }
        .onChange(of: scenePhase) { _, phase in setLive(phase == .active) }
        .onChange(of: reduceMotion) { _, rm in setPlaying(playsOnAppear && !rm) }
    }

    /// Public hook callers can use to start/stop the bounce loop.
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
}

#Preview("Fallback PNG · Dark") {
    WingedScrollRiveView(size: 220, fallbackImageName: "OnboardingLogo1")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .preferredColorScheme(.dark)
}
