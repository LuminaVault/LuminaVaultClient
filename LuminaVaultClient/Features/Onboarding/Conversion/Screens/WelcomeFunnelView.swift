// HER-287 — Screen 1: Welcome.
import SwiftUI

struct WelcomeFunnelView: View {
    @Bindable var state: ConversionFunnelState
    @Environment(\.lvPalette) private var palette

    var body: some View {
        FunnelScreenChrome(
            headline: "An AI that actually knows you.",
            subhead: "Your captures. Your voice. One Lumina.",
            primaryCTA: "Show me how →",
            onPrimary: { state.advance() }
        ) {
            VStack(spacing: 24) {
                HermieMascotView(state: .idle, size: 180, fallbackImageName: "OnboardingMascot")
                    .lvPulse()
                    .padding(.top, 24)
                heroPreview
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var heroPreview: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 10) {
                    Circle()
                        .fill(palette.accent.opacity(0.25))
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(palette.surface)
                            .frame(width: 180 - CGFloat(i * 20), height: 8)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(palette.surface.opacity(0.65))
                            .frame(width: 240 - CGFloat(i * 30), height: 6)
                    }
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(palette.surface.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(palette.glowPrimary.opacity(0.25), lineWidth: 1)
                        )
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}
