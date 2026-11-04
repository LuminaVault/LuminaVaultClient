// LuminaVaultClient/LuminaVaultClient/Components/LVLogoMark.swift
//
// Renders the LuminaVault mark — the gold winged "L" with the cyan memory
// star — on auth and splash surfaces.
//
// Memory Keeper (2026-10): the mark carries its own light, so the cosmic orb,
// amber halo, sparkle field, rim and perpetual breathing are gone. What is
// left is the mark and, in dark mode only, one faint cyan bloom that reads as
// the star's glow rather than a backdrop.
//
// Asset state today:
//   - Bundle asset: "WingedScroll" — the mark, cut from the key art. Dark
//     appearance = the keyed gold/cyan artwork; light = a deep-gold trace
//     (LuminaAssets/memory-keeper/README.md).
//   - Rive file: "lumina_anims.riv" artboard `winged_scroll` — absent. The
//     runtime keeps using the static fallback until it lands.
import SwiftUI

struct LVLogoMark: View {

    @Environment(\.lvPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    enum Size {
        case auth, splash
        case custom(CGFloat)
    }

    enum Intensity {
        case subtle, standard, hero
    }

    var size: Size = .auth
    var intensity: Intensity = .standard
    /// Kept for call-site compatibility; the static mark no longer animates.
    var animated: Bool = true
    /// Kept for call-site compatibility; the sparkle field was retired.
    var showSparkle: Bool = false

    var body: some View {
        WingedScrollRiveView(size: resolvedSize, playsOnAppear: animated)
            .shadow(color: palette.glowPrimary.opacity(bloomAlpha), radius: resolvedSize * 0.18)
            .frame(width: resolvedSize, height: resolvedSize)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("LuminaVault")
            .accessibilityAddTraits(.isImage)
    }

    private var resolvedSize: CGFloat {
        switch size {
        case .auth: return 112
        case .splash: return 200
        case .custom(let v): return v
        }
    }

    /// Bloom only in dark mode — on ivory a cyan halo reads as a smudge.
    private var bloomAlpha: Double {
        guard colorScheme == .dark else { return 0 }
        switch intensity {
        case .subtle: return 0.0
        case .standard: return 0.12
        case .hero: return 0.20
        }
    }
}

#Preview("Auth · Dark") {
    LVLogoMark(size: .auth)
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

#Preview("Auth · Light") {
    LVLogoMark(size: .auth, intensity: .subtle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .preferredColorScheme(.light)
}
