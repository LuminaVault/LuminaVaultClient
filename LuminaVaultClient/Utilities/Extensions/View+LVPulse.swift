// LuminaVaultClient/LuminaVaultClient/Utilities/Extensions/View+LVPulse.swift
import SwiftUI

extension View {
    /// Soft repeating scale + glow opacity pulse, palette-tinted.
    /// Pass `active: false` to freeze it (used to gate the tab-bar Home pulse
    /// behind "there are pending insights"). Respects Reduce Motion.
    func lvPulse(active: Bool = true) -> some View {
        modifier(LVPulseModifier(active: active))
    }

    /// Tap feedback: scale down + brief glow flash on press, palette-tinted.
    func lvGlowPress() -> some View {
        modifier(LVGlowPressModifier())
    }
}

private struct LVPulseModifier: ViewModifier {
    @Environment(\.lvPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let active: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .shadow(color: palette.glowPrimary.opacity(glow), radius: 14)
            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: phase)
            .onAppear { if active && !reduceMotion { phase = 1 } }
            .onChange(of: active) { _, on in
                if reduceMotion { phase = 0; return }
                phase = on ? 1 : 0
            }
    }

    private var scale: CGFloat { 1 + (active && !reduceMotion ? phase * 0.06 : 0) }
    private var glow: Double { active && !reduceMotion ? 0.4 + Double(phase) * 0.4 : 0 }
}

private struct LVGlowPressModifier: ViewModifier {
    @Environment(\.lvPalette) private var palette
    @GestureState private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.97 : 1)
            .shadow(color: palette.glowPrimary.opacity(isPressed ? 0.6 : 0), radius: 16)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in state = true }
            )
    }
}
