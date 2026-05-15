// LuminaVaultClient/LuminaVaultClient/Components/SparkleField.swift
import SwiftUI

struct SparkleField: View {
    var density: Int = 10
    var seed: UInt64 = 0xC05_5_C0DE
    var maxRadius: CGFloat = 1.8
    var driftSpeed: Double = 1.0
    var palette: [Color] = [Color.lvCyan, Color.lvAmber, Color.white]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let particles = buildParticles()

        if reduceMotion {
            Canvas { ctx, size in
                drawParticles(particles, t: 0, in: &ctx, size: size)
            }
            .allowsHitTesting(false)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                Canvas { ctx, size in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    drawParticles(particles, t: t, in: &ctx, size: size)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func buildParticles() -> [SparkleParticle] {
        var rng = SeededRNG(state: seed)
        return (0..<density).map { _ in
            SparkleParticle(
                angle0: rng.nextDouble() * .pi * 2,
                radiusRatio: 0.55 + rng.nextDouble() * 0.55,
                radiusJitterRatio: 0.04 + rng.nextDouble() * 0.06,
                omega: 0.08 + rng.nextDouble() * 0.14,
                phase: rng.nextDouble() * .pi * 2,
                dotRadius: 0.9 + rng.nextDouble() * (maxRadius - 0.9),
                paletteIdx: rng.nextInt(upperBound: palette.count)
            )
        }
    }

    private func drawParticles(
        _ particles: [SparkleParticle],
        t: Double,
        in ctx: inout GraphicsContext,
        size: CGSize
    ) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let baseRadius = min(size.width, size.height) / 2

        for p in particles {
            let driftT = t * driftSpeed
            let r = baseRadius * (p.radiusRatio
                + p.radiusJitterRatio * sin(driftT * p.omega + p.phase))
            let theta = p.angle0 + driftT * p.omega * 0.4
            let x = center.x + r * CGFloat(cos(theta))
            let y = center.y + r * CGFloat(sin(theta))

            let twinkle = sin(driftT * p.omega + p.phase)
            let alpha = 0.30 + 0.55 * (twinkle * twinkle)
            let color = palette[p.paletteIdx].opacity(alpha)

            let rect = CGRect(
                x: x - p.dotRadius,
                y: y - p.dotRadius,
                width: p.dotRadius * 2,
                height: p.dotRadius * 2
            )

            var sub = ctx
            sub.addFilter(.blur(radius: 0.8))
            sub.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }
}

private struct SparkleParticle {
    let angle0: Double
    let radiusRatio: Double
    let radiusJitterRatio: Double
    let omega: Double
    let phase: Double
    let dotRadius: CGFloat
    let paletteIdx: Int
}

private struct SeededRNG {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }

    mutating func nextDouble() -> Double {
        let v = next() >> 11
        return Double(v) / Double(1 &<< 53)
    }

    mutating func nextInt(upperBound: Int) -> Int {
        Int(next() % UInt64(upperBound))
    }
}

#Preview("SparkleField · Dark") {
    SparkleField(density: 12)
        .frame(width: 200, height: 200)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .preferredColorScheme(.dark)
}

#Preview("SparkleField · Light") {
    SparkleField(density: 12)
        .frame(width: 200, height: 200)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .preferredColorScheme(.light)
}
