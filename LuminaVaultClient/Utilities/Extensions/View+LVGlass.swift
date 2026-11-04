// LuminaVaultClient/LuminaVaultClient/Utilities/Extensions/View+LVGlass.swift
import SwiftUI

extension View {
    /// Wrap the view in a card: the palette surface over a material, a
    /// hairline `surfaceStroke`, and a faint palette glow.
    ///
    /// Memory Keeper (2026-10) retired the white top sheen, the cyan-fading
    /// gradient stroke and the double glow: a card is bounded by its edge, not
    /// lit. `intensity` still scales the glow, now capped low enough that a
    /// screen of cards reads the same with glow on or off.
    ///
    /// - Parameters:
    ///   - cornerRadius: corner radius of the card shape.
    ///   - intensity: 0...1 glow strength. 0.6 is a comfortable default.
    ///   - material: SwiftUI material behind the glass fill. Use `.regularMaterial`
    ///     for composer strips and other high-touch OS chrome.
    func lvGlassCard(
        cornerRadius: CGFloat = 20,
        intensity: CGFloat = 0.6,
        material: Material = .ultraThinMaterial
    ) -> some View {
        modifier(LVGlassCardModifier(cornerRadius: cornerRadius, intensity: intensity, material: material))
    }

    /// A glowing pill or capsule outline using palette.glowPrimary.
    func lvGlowStroke(cornerRadius: CGFloat = 16, intensity: CGFloat = 0.7) -> some View {
        modifier(LVGlowStrokeModifier(cornerRadius: cornerRadius, intensity: intensity))
    }

    /// HER-300 — premium-CTA gold ring. A `palette.accent` → `palette.glowPrimary`
    /// gradient stroke paired with a soft outer amber glow. Reserved for the single
    /// most important call-to-action on a screen (e.g. Home's "Sync & Learn" pill).
    ///
    /// Pair with `palette.surface` fill underneath; the modifier only paints the
    /// ring + glow, not the fill, so it composes with `lvGlassCard` or a custom
    /// background.
    func lvAuroraGoldRing(cornerRadius: CGFloat = 20, intensity: CGFloat = 1.0) -> some View {
        modifier(LVAuroraGoldRingModifier(cornerRadius: cornerRadius, intensity: intensity))
    }

    /// HER-306 — inner-rim cyan glow. A soft `palette.glowPrimary` halo painted
    /// on the inside of a shape's edge. Pairs with `.lvGlassCard` to give
    /// cards a "lit from within" feel.
    func lvInnerGlow(cornerRadius: CGFloat = 20, intensity: CGFloat = LVGlow.card) -> some View {
        modifier(LVInnerGlowModifier(cornerRadius: cornerRadius, intensity: intensity))
    }
}

private struct LVGlassCardModifier: ViewModifier {
    @Environment(\.lvPalette) private var palette
    let cornerRadius: CGFloat
    let intensity: CGFloat
    let material: Material

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(material)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(palette.surface)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(palette.surfaceStroke, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: palette.glowPrimary.opacity(0.10 * intensity), radius: 18)
    }
}

private struct LVInnerGlowModifier: ViewModifier {
    @Environment(\.lvPalette) private var palette
    let cornerRadius: CGFloat
    let intensity: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(palette.glowPrimary.opacity(0.30 * intensity), lineWidth: 1)
                .blur(radius: 6)
                .mask(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(lineWidth: 14)
                )
        }
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
                    .stroke(palette.glowPrimary.opacity(0.75 * intensity), lineWidth: 1.2)
            }
            .shadow(color: palette.glowPrimary.opacity(0.15 * intensity), radius: 10)
    }
}

private struct LVAuroraGoldRingModifier: ViewModifier {
    @Environment(\.lvPalette) private var palette
    let cornerRadius: CGFloat
    let intensity: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                palette.accent.opacity(0.95 * intensity),
                                palette.glowPrimary.opacity(0.5 * intensity),
                                palette.accent.opacity(0.95 * intensity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
            .shadow(color: palette.accent.opacity(0.25 * intensity), radius: 12)
    }
}
