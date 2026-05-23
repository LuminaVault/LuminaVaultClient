// HER-287 — Screen 9: Processing (anticipation builder, auto-advances).
import SwiftUI

struct ProcessingView: View {
    @Bindable var state: ConversionFunnelState
    @Environment(\.lvPalette) private var palette

    var body: some View {
        VStack(spacing: 24) {
            HermieMascotView(state: .thinking, size: 140, fallbackImageName: "OnboardingMascot")
                .lvPulse()
            VStack(spacing: 8) {
                Text("Building your first Lumina query…")
                    .font(.system(size: 20, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text("Hermie is wiring your picks into a demo vault.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            ProgressView()
                .tint(palette.glowPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            state.advance()
        }
    }
}
