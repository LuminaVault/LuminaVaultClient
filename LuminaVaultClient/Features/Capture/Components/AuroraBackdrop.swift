// LuminaVaultClient/LuminaVaultClient/Features/Capture/Components/AuroraBackdrop.swift
//
// HER-305 — radial-gradient backdrop for the Capture sheet. Three
// stacked radials at low intensity (aurora top, bottom, center)
// produce a soft cinematic glow that reads as depth, not decoration.

import SwiftUI

struct AuroraBackdrop: View {
    @Environment(\.lvPalette) private var palette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                RadialGradient(
                    colors: [palette.auroraTop, .clear],
                    center: UnitPoint(x: 0.85, y: 0.0),
                    startRadius: 0,
                    endRadius: max(w, h) * 0.75
                )

                RadialGradient(
                    colors: [palette.auroraBottom, .clear],
                    center: UnitPoint(x: 0.15, y: 1.0),
                    startRadius: 0,
                    endRadius: max(w, h) * 0.85
                )

                RadialGradient(
                    colors: [palette.auroraCenter, .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(w, h) * 0.55
                )
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    AuroraBackdrop()
        .background(LVPalette.cyanGoldDark.backgroundBase)
        .preferredColorScheme(.dark)
}
