// LuminaVaultClient/LuminaVaultClient/Components/HVLogoMark.swift
//
// Renders the LuminaVault winged-scroll brand mark with a layered cosmic
// halo, optional sparkle particles, and a Rive-backed wing animation
// (falls back to a static PNG with a subtle scale breathing).
//
// Asset state today:
//   - Bundle asset: "WingedScroll" — placeholder JPG, swap to transparent
//     PNG when the designer delivers (see Resources/WingedScroll/README.md).
//   - Rive file: "winged_scroll.riv" — absent. Runtime auto-uses fallback
//     until this lands.
import SwiftUI

struct LVLogoMark: View {
    enum Size {
        case auth, splash
        case custom(CGFloat)
    }

    enum Intensity {
        case subtle, standard, hero
    }

    var size: Size = .auth
    var intensity: Intensity = .standard
    var animated: Bool = true
    var showSparkle: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var breathScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.85
    @State private var amberDriftX: CGFloat = 0
    @State private var amberDriftY: CGFloat = 0

    var body: some View {
        ZStack {
            orbLayer
            amberHaloLayer
            sparkleLayer
            scrollLayer
            rimLayer
        }
        .frame(width: resolvedSize * orbScale, height: resolvedSize * orbScale)
        .onAppear(perform: startAnimations)
    }

    // MARK: - Layers

    private var orbLayer: some View {
        let d = resolvedSize
        let orb = d * orbScale
        return Circle()
            .fill(orbGradient)
            .frame(width: orb, height: orb)
            .blur(radius: d * 0.08)
            .scaleEffect(breathScale)
            .opacity(glowOpacity)
    }

    private var amberHaloLayer: some View {
        let d = resolvedSize
        let orb = d * orbScale
        return Circle()
            .fill(amberHaloGradient(orbRadius: orb))
            .frame(width: orb * 0.95, height: orb * 0.95)
            .blur(radius: d * 0.12)
            .blendMode(.screen)
            .scaleEffect(breathScale)
            .offset(x: amberDriftX, y: amberDriftY)
    }

    @ViewBuilder
    private var sparkleLayer: some View {
        if showSparkle {
            let orb = resolvedSize * orbScale
            SparkleField(density: sparkleDensity)
                .frame(width: orb, height: orb)
        }
    }

    private var scrollLayer: some View {
        WingedScrollRiveView(size: resolvedSize)
            .shadow(color: Color.lvCyan.opacity(glowCyanAlpha), radius: glowCyanRadius)
            .shadow(color: Color.lvAmber.opacity(glowAmberAlpha), radius: glowAmberRadius)
    }

    @ViewBuilder
    private var rimLayer: some View {
        let d = resolvedSize
        if intensity != .subtle {
            Circle()
                .stroke(rimGradient, lineWidth: 1)
                .frame(width: d * 0.96, height: d * 0.96)
                .blur(radius: 0.6)
                .opacity(0.35)
        }
    }

    // MARK: - Gradients

    private var orbGradient: RadialGradient {
        let orb = resolvedSize * orbScale
        return RadialGradient(
            colors: [
                Color.lvCyan.opacity(0.35 * alphaScale),
                Color.lvBlue.opacity(0.18 * alphaScale),
                Color.clear
            ],
            center: .center,
            startRadius: 0,
            endRadius: orb / 2
        )
    }

    private func amberHaloGradient(orbRadius: CGFloat) -> RadialGradient {
        RadialGradient(
            colors: [
                Color.lvAmber.opacity(0.22 * alphaScale),
                Color.clear
            ],
            center: .topTrailing,
            startRadius: 0,
            endRadius: orbRadius * 0.425
        )
    }

    private var rimGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.lvCyan.opacity(0.5),
                Color.clear,
                Color.lvAmber.opacity(0.35)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Resolved values

    private var resolvedSize: CGFloat {
        switch size {
        case .auth: return 112
        case .splash: return 240
        case .custom(let v): return v
        }
    }

    private var orbScale: CGFloat {
        switch intensity {
        case .subtle: return 1.35
        case .standard: return 1.55
        case .hero: return 1.85
        }
    }

    private var glowCyanAlpha: Double {
        switch intensity {
        case .subtle: return 0.22
        case .standard: return 0.38
        case .hero: return 0.55
        }
    }

    private var glowCyanRadius: CGFloat {
        switch intensity {
        case .subtle: return 24
        case .standard: return 36
        case .hero: return 60
        }
    }

    private var glowAmberAlpha: Double {
        switch intensity {
        case .subtle: return 0.10
        case .standard: return 0.18
        case .hero: return 0.28
        }
    }

    private var glowAmberRadius: CGFloat {
        switch intensity {
        case .subtle: return 48
        case .standard: return 70
        case .hero: return 100
        }
    }

    private var sparkleDensity: Int {
        switch intensity {
        case .subtle: return 8
        case .standard: return 12
        case .hero: return 16
        }
    }

    private var alphaScale: Double {
        colorScheme == .dark ? 1.0 : 0.55
    }

    // MARK: - Animation

    private func startAnimations() {
        guard animated, !reduceMotion else {
            breathScale = 1.0225
            glowOpacity = 0.975
            return
        }

        withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
            breathScale = 1.045
        }
        withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) {
            glowOpacity = 1.10
        }
        withAnimation(.easeInOut(duration: 7.0).repeatForever(autoreverses: true)) {
            amberDriftX = 2
            amberDriftY = -3
        }
    }
}

#Preview("Auth · Standard · Sparkles · Dark") {
    LVLogoMark(size: .auth, intensity: .standard, showSparkle: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .preferredColorScheme(.dark)
}

#Preview("Splash · Hero · Sparkles · Dark") {
    LVLogoMark(size: .splash, intensity: .hero, showSparkle: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .preferredColorScheme(.dark)
}

#Preview("Auth · Subtle · NoSparkle · Light") {
    LVLogoMark(size: .auth, intensity: .subtle, showSparkle: false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .preferredColorScheme(.light)
}
