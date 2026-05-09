// LuminaVaultClient/LuminaVaultClient/Utilities/Extensions/View+LVBackground.swift
import SwiftUI

extension View {
    func lvBackground() -> some View {
        modifier(LVBackgroundModifier())
    }
}

private struct LVBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        ZStack {
            Color.lvNavy.ignoresSafeArea()

            // Star field — dark mode only
            if scheme == .dark {
                LVStarField().ignoresSafeArea()
            }

            GeometryReader { geo in
                // Amber aurora — top-trailing
                RadialGradient(
                    colors: [Color.lvAmber.opacity(scheme == .dark ? 0.18 : 0.09), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: geo.size.width * 0.85
                )
                .ignoresSafeArea()
                // Cyan nebula — bottom-leading
                RadialGradient(
                    colors: [Color.lvCyan.opacity(scheme == .dark ? 0.14 : 0.08), .clear],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: geo.size.width * 0.75
                )
                .ignoresSafeArea()
                // Blue mid-depth pulse
                RadialGradient(
                    colors: [Color.lvBlue.opacity(scheme == .dark ? 0.08 : 0.05), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: geo.size.width * 0.55
                )
                .ignoresSafeArea()
            }

            content
        }
    }
}

private struct LVStarField: View {
    private struct Star {
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
        let opacity: Double
    }

    private static func makeStars() -> [Star] {
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
    }

    private let stars: [Star] = LVStarField.makeStars()

    var body: some View {
        GeometryReader { geo in
            ForEach(0..<stars.count, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(stars[i].opacity))
                    .frame(width: stars[i].radius * 2, height: stars[i].radius * 2)
                    .position(
                        x: stars[i].x * geo.size.width,
                        y: stars[i].y * geo.size.height
                    )
            }
        }
    }
}
