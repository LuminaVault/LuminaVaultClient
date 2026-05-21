// LuminaVaultClient/LuminaVaultClient/Utilities/Extensions/View+LVGlass.swift
import SwiftUI

extension View {
    /// Wrap the view in a glass-morphic card: thin material, gradient stroke,
    /// and a soft outer glow tinted by the active palette.
    ///
    /// - Parameters:
    ///   - cornerRadius: corner radius of the card shape.
    ///   - intensity: 0...1 glow strength. 0.6 is a comfortable default.
    func lvGlassCard(cornerRadius: CGFloat = 20, intensity: CGFloat = 0.6) -> some View {
        modifier(LVGlassCardModifier(cornerRadius: cornerRadius, intensity: intensity))
    }

    /// A glowing pill or capsule outline using palette.glowPrimary.
    func lvGlowStroke(cornerRadius: CGFloat = 16, intensity: CGFloat = 0.7) -> some View {
        modifier(LVGlowStrokeModifier(cornerRadius: cornerRadius, intensity: intensity))
    }
}

private struct LVGlassCardModifier: ViewModifier {
    @Environment(\.lvPalette) private var palette
    let cornerRadius: CGFloat
    let intensity: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(palette.surface)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.05), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                palette.surfaceStroke,
                                palette.glowPrimary.opacity(0.25),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: palette.glowPrimary.opacity(0.45 * intensity), radius: 22)
            .shadow(color: palette.glowSecondary.opacity(0.18 * intensity), radius: 40)
    }
}

private struct LVGlowStrokeModifier: ViewModifier {
    @Environment(\.lvPalette) private var palette
    let cornerRadius: CGFloat
    let intensity: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(palette.glowPrimary.opacity(intensity), lineWidth: 1.2)
            }
            .shadow(color: palette.glowPrimary.opacity(0.55 * intensity), radius: 14)
            .shadow(color: palette.glowSecondary.opacity(0.2 * intensity), radius: 28)
    }
}
