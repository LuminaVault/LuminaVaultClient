// LuminaVaultClient/LuminaVaultClient/Components/LVHaloBackdrop.swift
import SwiftUI

/// Concentric cyan/secondary radial glows + slow-drifting palette-tinted dust
/// behind a hero focal element (mascot, splash icon). Composed of pure SwiftUI —
/// no assets, no Rive, no Timer.
struct LVHaloBackdrop: View {

    @Environment(\.lvPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let focalSize: CGFloat
    var intensity: CGFloat = LVGlow.hero
    var particleCount: Int = 10

    @State private var driftPhase: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [palette.glowPrimary.opacity(intensity), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: focalSize * 0.9
                    )
                )
                .frame(width: focalSize * 2.2, height: focalSize * 2.2)
                .blur(radius: 40)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [palette.glowSecondary.opacity(0.28 * (intensity / LVGlow.hero)), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: focalSize * 0.5
                    )
                )
                .frame(width: focalSize * 1.4, height: focalSize * 1.4)
                .blur(radius: 24)

            LVDustField(orbitRadius: focalSize * 0.95, phase: driftPhase, count: particleCount)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                driftPhase = 1
            }
        }
    }
}

private struct LVDustField: View {

    @Environment(\.lvPalette) private var palette

    let orbitRadius: CGFloat
    let phase: CGFloat
    let count: Int

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let p = Particle.make(index: i, count: count)
                let angle = p.baseAngle + phase * 2 * .pi * p.angularSpeed
                let r = orbitRadius * p.radiusRatio
                Circle()
                    .fill(palette.glowPrimary.opacity(p.opacity))
                    .frame(width: p.size, height: p.size)
                    .blur(radius: p.blur)
                    .offset(
                        x: cos(angle) * r,
                        y: sin(angle) * r * p.verticalSquash
                    )
            }
        }
    }

    private struct Particle {
        let baseAngle: Double
        let angularSpeed: Double
        let radiusRatio: CGFloat
        let size: CGFloat
        let opacity: Double
        let blur: CGFloat
        let verticalSquash: CGFloat

        static func make(index i: Int, count: Int) -> Particle {
            let baseAngle = (Double(i) / Double(count)) * 2 * .pi + Double(i * 37 % 100) / 100.0
            let angularSpeed = 0.4 + Double((i * 17) % 6) * 0.08
            let radiusRatio = 0.55 + CGFloat((i * 13) % 50) / 100.0
            let size = 2 + CGFloat((i * 11) % 5)
            let opacity = 0.18 + Double((i * 23) % 5) * 0.05
            let blur = 1 + CGFloat((i * 7) % 3)
            let verticalSquash = 0.55 + CGFloat((i * 29) % 30) / 100.0
            return Particle(
                baseAngle: baseAngle,
                angularSpeed: angularSpeed,
                radiusRatio: radiusRatio,
                size: size,
                opacity: opacity,
                blur: blur,
                verticalSquash: verticalSquash
            )
        }
    }
}

#Preview("LVHaloBackdrop · Dark") {
    LVHaloBackdrop(focalSize: 280)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .preferredColorScheme(.dark)
}
