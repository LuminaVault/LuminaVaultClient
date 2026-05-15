// LuminaVaultClient/LuminaVaultClient/Components/WingedScrollRiveView.swift
import SwiftUI
import RiveRuntime

struct WingedScrollRiveView: View {
    var size: CGFloat = 220
    var fallbackImageName: String = "WingedScroll"
    var fireFlapOnAppear: Bool = true

    @State private var viewModel: RiveViewModel?
    @State private var fallbackBreathing: CGFloat = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let riveFileName = "winged_scroll"
    private static let stateMachineName = "State Machine 1"
    private static let flapInput = "flap"

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
            }
        }
        .accessibilityLabel("LuminaVault winged-scroll mark")
        .task { loadIfAvailable() }
        .onAppear { startFallbackBreathing() }
    }

    /// Public hook callers can use to fire the flap trigger on success events.
    func fireFlap() {
        viewModel?.triggerInput(Self.flapInput)
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
        if fireFlapOnAppear {
            vm.triggerInput(Self.flapInput)
        }
    }

    private func startFallbackBreathing() {
        guard viewModel == nil, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
            fallbackBreathing = 1.025
        }
    }
}

#Preview("Fallback PNG · Dark") {
    WingedScrollRiveView(size: 220, fallbackImageName: "OnboardingLogo1")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .preferredColorScheme(.dark)
}
