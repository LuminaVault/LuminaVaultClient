// LuminaVaultClient/LuminaVaultClient/Components/GetStartedHeroRiveView.swift
import SwiftUI
import RiveRuntime

struct GetStartedHeroRiveView: View {

    /// Width in points. The artboard contract is 1280×720, so the view is
    /// 16:9 — the key-art fallback is the same scene, full-bleed.
    var size: CGFloat = 240
    var fallbackImageName: String = "GetStartedHero"
    var playsOnAppear: Bool = true

    @State private var viewModel: RiveViewModel?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private static let riveFileName = "lumina_anims"
    private static let artboardName = "get_started_hero"
    private static let stateMachineName = "State Machine 1"
    private static let isPlayingInput = "isPlaying"

    var body: some View {
        Group {
            if let viewModel {
                viewModel.view()
                    .frame(width: size, height: size * 9 / 16)
            } else {
                // Static: the key art already carries its own light and depth.
                Image(fallbackImageName)
                    .resizable()
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(width: size, height: size * 9 / 16)
                    .clipped()
            }
        }
        .accessibilityLabel("Lumina, the keeper of memories, reading a glowing scroll in the vault library")
        .task { loadIfAvailable() }
        .onAppear { setLive(true) }
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
}

#Preview("Fallback PNG · Dark") {
    GetStartedHeroRiveView(size: 240)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .preferredColorScheme(.dark)
}
