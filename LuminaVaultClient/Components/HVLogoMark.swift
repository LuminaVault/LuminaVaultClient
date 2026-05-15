// LuminaVaultClient/LuminaVaultClient/Components/HVLogoMark.swift
//
// PATH B (when a transparent OnboardingLogo1Mark asset lands):
//   1. Swap `assetName` to the transparent version.
//   2. Delete the `.mask(...)` modifier on the logo Image in `logoLayer`.
//   3. Delete the `.overlay(...multiply)` modifier on the logo Image in `logoLayer`.
//   4. Bump Size diameters ×1.08 (transparent assets typically have less internal padding).
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

    private let assetName = "OnboardingLogo1"

    var body: some View {
        ZStack {
            orbLayer
            amberHaloLayer
            logoLayer
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

    private var logoLayer: some View {
        let d = resolvedSize
        return Image(assetName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: d, height: d)
            .mask(logoMask(diameter: d))
            .overlay(logoTone(diameter: d))
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
                .opacity(0.85)
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

    private func logoMask(diameter d: CGFloat) -> RadialGradient {
        RadialGradient(
            colors: [
                Color.black,
                Color.black.opacity(0.92),
                Color.clear
            ],
            center: .center,
            startRadius: d * 0.38,
            endRadius: d * 0.52
        )
    }

    private func logoTone(diameter d: CGFloat) -> some View {
        RadialGradient(
            colors: [
                Color.clear,
                Color.lvBlue.opacity(0.18 * alphaScale)
            ],
            center: .center,
            startRadius: d * 0.20,
            endRadius: d * 0.55
        )
        .blendMode(.multiply)
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

#Preview("Auth · Standard · Dark") {
    LVLogoMark(size: .auth, intensity: .standard)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .preferredColorScheme(.dark)
}

#Preview("Splash · Hero · Dark") {
    LVLogoMark(size: .splash, intensity: .hero)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .preferredColorScheme(.dark)
}

#Preview("Auth · Subtle · Light") {
    LVLogoMark(size: .auth, intensity: .subtle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .preferredColorScheme(.light)
}
