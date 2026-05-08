// HermesVaultClient/HermesVaultClient/Utilities/Extensions/View+HVBackground.swift
import SwiftUI

extension View {
    func hvBackground() -> some View {
        modifier(HVBackgroundModifier())
    }
}

private struct HVBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            Color.hvNavy.ignoresSafeArea()
            GeometryReader { geo in
                RadialGradient(
                    colors: [Color.hvAmber.opacity(0.12), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: geo.size.width * 0.65
                )
                .ignoresSafeArea()
                RadialGradient(
                    colors: [Color.hvCyan.opacity(0.09), .clear],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: geo.size.width * 0.55
                )
                .ignoresSafeArea()
            }
            content
        }
    }
}
