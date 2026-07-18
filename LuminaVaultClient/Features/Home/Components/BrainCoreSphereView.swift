// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/BrainCoreSphereView.swift
//
// Lightweight neural-sphere preview for the Home Command Center hero.
// Pure SwiftUI Canvas — not the full BrainGraphCanvas force simulation.

import SwiftUI

struct BrainCoreSphereView: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var size: CGFloat = 180

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 : 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let radius = min(canvasSize.width, canvasSize.height) * 0.38

                // Soft outer glow
                let glowRect = CGRect(
                    x: center.x - radius * 1.35,
                    y: center.y - radius * 1.35,
                    width: radius * 2.7,
                    height: radius * 2.7
                )
                context.fill(
                    Path(ellipseIn: glowRect),
                    with: .radialGradient(
                        Gradient(colors: [
                            palette.glowPrimary.opacity(0.35),
                            palette.accent.opacity(0.12),
                            .clear
                        ]),
                        center: center,
                        startRadius: radius * 0.2,
                        endRadius: radius * 1.4
                    )
                )

                // Concentric rings
                for i in 0..<4 {
                    let r = radius * (0.45 + CGFloat(i) * 0.18)
                    var ring = Path()
                    ring.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                    context.stroke(
                        ring,
                        with: .color(palette.glowPrimary.opacity(0.18 + Double(i) * 0.05)),
                        lineWidth: 1
                    )
                }

                // Orbiting nodes
                let nodeCount = 28
                for i in 0..<nodeCount {
                    let angle = (Double(i) / Double(nodeCount)) * .pi * 2
                        + t * (0.25 + Double(i % 5) * 0.03)
                    let orbit = radius * (0.55 + 0.35 * sin(Double(i) * 0.7 + t * 0.4))
                    let x = center.x + CGFloat(cos(angle) * orbit)
                    let y = center.y + CGFloat(sin(angle) * orbit * 0.72)
                    let nodeR: CGFloat = i % 4 == 0 ? 3.2 : 2.0
                    let nodeRect = CGRect(x: x - nodeR, y: y - nodeR, width: nodeR * 2, height: nodeR * 2)
                    context.fill(
                        Path(ellipseIn: nodeRect),
                        with: .color(palette.glowPrimary.opacity(0.55 + 0.35 * sin(t + Double(i))))
                    )
                }

                // Core
                let coreR = radius * 0.22
                let coreRect = CGRect(x: center.x - coreR, y: center.y - coreR, width: coreR * 2, height: coreR * 2)
                context.fill(
                    Path(ellipseIn: coreRect),
                    with: .radialGradient(
                        Gradient(colors: [
                            .white.opacity(0.85),
                            palette.glowPrimary.opacity(0.9),
                            palette.accent.opacity(0.5)
                        ]),
                        center: center,
                        startRadius: 0,
                        endRadius: coreR
                    )
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Brain core preview")
    }
}
