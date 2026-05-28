// LuminaVaultClient/LuminaVaultClient/Utilities/Extensions/View+LVParticleBackground.swift
//
// HER-300 — Particle / neural-network background overlay. Layered above
// `lvBackground()`'s aurora gradients and beneath content. Reserved for
// hero surfaces where the cinematic depth is worth the extra render cost:
// Home empty-state, Onboarding, full-screen mascot moments. Avoid on
// dense scroll surfaces (list views, settings) — it competes with copy.
import SwiftUI

enum LVParticleIntensity: CaseIterable, Sendable {
    case subtle
    case standard
    case hero

    var opacity: Double {
        switch self {
        case .subtle:   return 0.10
        case .standard: return 0.18
        case .hero:     return 0.28
        }
    }
}

extension View {
    /// HER-300 — Overlay the cosmic neural-network particle field. Stack
    /// above `lvBackground()` and beneath content. See §13 of
    /// `docs/DESIGN_SYSTEM.md` for placement rules.
    func lvParticleBackground(intensity: LVParticleIntensity = .standard) -> some View {
        background(LVParticleBackgroundLayer(intensity: intensity))
    }
}

private struct LVParticleBackgroundLayer: View {
    let intensity: LVParticleIntensity

    var body: some View {
        Image("Lumina/Backgrounds/neural-network")
            .resizable()
            .scaledToFill()
            .opacity(intensity.opacity)
            .blendMode(.screen)
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
