// LuminaVaultClient/LuminaVaultClient/Utilities/Extensions/View+LVMotif.swift
import SwiftUI

extension View {
    /// Identity sigil frame: a hairline `palette.surfaceStroke` rounded-rect
    /// outline plus two ~10pt L-shaped corner ticks (top-leading and
    /// bottom-trailing) in `palette.glowPrimary`. Overlay only — composes
    /// with `lvGlassCard` or a plain background underneath.
    func lvSigilFrame(cornerRadius: CGFloat = LVRadius.lg) -> some View {
        modifier(LVSigilFrameModifier(cornerRadius: cornerRadius))
    }

    /// Constellation backdrop: a static dot grid in faint `palette.glowPrimary`
    /// drawn behind the content. Single `Canvas` pass — no timers, no
    /// animation — so it is cheap enough for full-screen use.
    func lvConstellationBackdrop(spacing: CGFloat = 34) -> some View {
        modifier(LVConstellationBackdropModifier(spacing: spacing))
    }
}

/// 1px "vault seam" divider — `palette.surfaceStroke` passing through a faint
/// `palette.accent` core, transparent at both ends. Drop between content
/// groups where a plain `Divider()` would lose the identity.
struct LVVaultSeam: View {
    @Environment(\.lvPalette) private var palette

    var body: some View {
        LinearGradient(
            colors: [
                .clear,
                palette.surfaceStroke,
                palette.accent.opacity(0.35),
                palette.surfaceStroke,
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .accessibilityHidden(true)
    }
}

private struct LVSigilFrameModifier: ViewModifier {
    @Environment(\.lvPalette) private var palette
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(palette.surfaceStroke, lineWidth: 1)
            }
            .overlay {
                LVSigilCornerTicks(length: 10)
                    .stroke(palette.glowPrimary.opacity(0.45), lineWidth: 1)
            }
    }
}

/// Two L-shaped reticle ticks at the top-leading and bottom-trailing corners.
private struct LVSigilCornerTicks: Shape {
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        return path
    }
}

private struct LVConstellationBackdropModifier: ViewModifier {
    @Environment(\.lvPalette) private var palette
    let spacing: CGFloat

    func body(content: Content) -> some View {
        content.background {
            Canvas { context, size in
                let shading = GraphicsContext.Shading.color(palette.glowPrimary.opacity(0.14))
                var y = spacing / 2
                while y < size.height {
                    var x = spacing / 2
                    while x < size.width {
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)),
                            with: shading
                        )
                        x += spacing
                    }
                    y += spacing
                }
            }
            .allowsHitTesting(false)
        }
    }
}

#Preview("Motifs") {
    VStack(spacing: LVSpacing.xl) {
        Text("Sigil frame")
            .padding(LVSpacing.xl)
            .lvSigilFrame()
        LVVaultSeam()
    }
    .padding(LVSpacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .lvConstellationBackdrop()
    .background(LVPalette.cyanGoldDark.backgroundBase)
    .environment(\.lvPalette, .cyanGoldDark)
}
