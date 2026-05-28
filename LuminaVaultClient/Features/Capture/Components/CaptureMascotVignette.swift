// LuminaVaultClient/LuminaVaultClient/Features/Capture/Components/CaptureMascotVignette.swift
//
// HER-305 — bottom-trailing mascot art behind the Capture sheet's
// glass cards. Low opacity, blurred, radial-masked so the figure
// fades into the aurora rather than reading as foreground decoration.

import SwiftUI

struct CaptureMascotVignette: View {
    /// Asset name from `Lumina/Mascot/*` (folder provides namespace).
    var assetName: String = "Lumina/Mascot/mascot_premium_1"
    var opacity: Double = 0.12
    var blur: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.85
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: side, height: side)
                .blur(radius: blur)
                .opacity(opacity)
                .mask {
                    RadialGradient(
                        colors: [.white, .white.opacity(0.6), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: side * 0.55
                    )
                }
                .frame(width: geo.size.width, height: geo.size.height,
                       alignment: .bottomTrailing)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        CaptureMascotVignette()
    }
    .preferredColorScheme(.dark)
}
