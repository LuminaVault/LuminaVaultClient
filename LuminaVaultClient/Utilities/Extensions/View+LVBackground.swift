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
            GeometryReader { geo in
                // Amber aurora — top-trailing
                RadialGradient(
                    colors: [Color.lvAmber.opacity(scheme == .dark ? 0.15 : 0.08), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: geo.size.width * 0.75
                )
                .ignoresSafeArea()
                // Cyan nebula — bottom-leading
                RadialGradient(
                    colors: [Color.lvCyan.opacity(scheme == .dark ? 0.12 : 0.07), .clear],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: geo.size.width * 0.65
                )
                .ignoresSafeArea()
                // Blue mid-depth pulse
                RadialGradient(
                    colors: [Color.lvBlue.opacity(scheme == .dark ? 0.07 : 0.04), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: geo.size.width * 0.5
                )
                .ignoresSafeArea()
            }
            content
        }
    }
}
