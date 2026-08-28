// LuminaVaultClient/LuminaVaultClient/Utilities/Extensions/View+LVBackground.swift
import SwiftUI

extension View {
    func lvBackground() -> some View {
        modifier(LVBackgroundModifier())
    }
}

private struct LVBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.lvPalette) private var palette
    @Environment(\.lvThemeManager) private var themeManager

    private var usesCinematicBackdrop: Bool {
        themeManager?.theme != .system
    }

    func body(content: Content) -> some View {
        ZStack {
            if usesCinematicBackdrop {
                LVCinematicBackdrop(palette: palette, showsStarField: scheme == .dark)
                    .ignoresSafeArea()
            } else {
                // `.system` keeps the plain fill — no washes, no starfield.
                palette.backgroundBase.ignoresSafeArea()
            }

            content
        }
    }
}

/// The branded backdrop — base fill, starfield, and three aurora washes — drawn
/// as a single rasterised pass.
///
/// This used to be four stacked layers: an opaque base `Color`, a
/// `GeometryReader` hosting three full-screen `RadialGradient`s, and a second
/// `GeometryReader` hosting 55 discrete `Circle` views. That is 58 view nodes
/// and two layout round-trips sitting behind the content of every one of the
/// ~75 `.lvBackground()` call sites — and since `.cyanGold` became the default
/// theme, it is what every user gets on first launch rather than an opt-in.
///
/// A `Canvas` paints exactly the same pixels in one draw into one layer, so the
/// backdrop's cost stops scaling with the number of stars and the washes stop
/// re-evaluating as three separate gradient layers on every geometry change.
/// Nothing here is animated, so the draw runs on size or palette changes only.
private struct LVCinematicBackdrop: View {
    let palette: LVPalette
    let showsStarField: Bool

    var body: some View {
        // `opaque: true` — the base fill covers every pixel (all branded
        // `backgroundBase` values are fully opaque), so the compositor can skip
        // the alpha channel for the whole backdrop.
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            let bounds = Path(CGRect(origin: .zero, size: size))
            context.fill(bounds, with: .color(palette.backgroundBase))

            // The starfield sits *under* the washes, matching the order it had
            // as a ZStack sibling.
            if showsStarField {
                for star in LVStarField.stars {
                    let center = CGPoint(x: star.x * size.width, y: star.y * size.height)
                    let diameter = star.radius * 2
                    context.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: center.x - star.radius,
                                y: center.y - star.radius,
                                width: diameter,
                                height: diameter
                            )
                        ),
                        with: .color(.white.opacity(star.opacity))
                    )
                }
            }

            // Top-trailing aurora wash (warm in cyanGold, pink in nebula, gold
            // in solar).
            context.fill(
                bounds,
                with: .radialGradient(
                    Gradient(colors: [palette.auroraTop, .clear]),
                    center: CGPoint(x: size.width, y: 0),
                    startRadius: 0,
                    endRadius: size.width * 0.85
                )
            )
            // Bottom-leading nebula wash.
            context.fill(
                bounds,
                with: .radialGradient(
                    Gradient(colors: [palette.auroraBottom, .clear]),
                    center: CGPoint(x: 0, y: size.height),
                    startRadius: 0,
                    endRadius: size.width * 0.75
                )
            )
            // Mid-depth pulse for added depth.
            context.fill(
                bounds,
                with: .radialGradient(
                    Gradient(colors: [palette.auroraCenter, .clear]),
                    center: CGPoint(x: size.width / 2, y: size.height / 2),
                    startRadius: 0,
                    endRadius: size.width * 0.55
                )
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Deterministic star placement for the cinematic backdrop.
///
/// The table is a `static let` so it is built once per process rather than once
/// per backdrop instantiation — it used to be a stored instance property on a
/// `View`, so all 55 stars were recomputed every time the backdrop was rebuilt.
private enum LVStarField {
    struct Star {
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
        let opacity: Double
    }

    static let stars: [Star] = {
        var result: [Star] = []
        result.reserveCapacity(55)
        for i in 0..<55 {
            let x = CGFloat((i * 127 + 31) % 100) / 100
            let y = CGFloat((i * 83 + 17) % 100) / 100
            let radius = CGFloat((i % 3) + 1) * 0.5
            let opacity = 0.20 + Double(i % 4) * 0.07
            result.append(Star(x: x, y: y, radius: radius, opacity: opacity))
        }
        return result
    }()
}
