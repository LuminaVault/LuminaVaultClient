// LuminaVaultClient/LuminaVaultClient/Components/LVFAB.swift
//
// HER-301 — Floating Action Button. Wraps the `Lumina/Icons/plus-circle`
// glowing brand glyph through the `LVIcon.plusCircleFill` token. The
// gold-ring + cyan-outer-glow combination matches the cinematic FAB in
// the HER-299 Stitch reference frames.
//
// Not yet wired into `MainTabView`'s capture spot — the tab-bar subtask
// under HER-299 does that. Shipping the component now means later
// subtasks just drop it in.
import SwiftUI
import UIKit

struct LVFAB: View {
    @Environment(\.lvPalette) private var palette

    let size: CGFloat
    let action: () -> Void

    init(size: CGFloat = 64, action: @escaping () -> Void) {
        self.size = size
        self.action = action
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            LVIconView(.plusCircleFill, size: size, tint: palette.glowPrimary)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(palette.surface)
                        .shadow(color: palette.glowPrimary.opacity(0.65), radius: 18)
                        .shadow(color: palette.accent.opacity(0.35), radius: 32)
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    palette.accent.opacity(0.9),
                                    palette.glowPrimary.opacity(0.5),
                                    palette.accent.opacity(0.9)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capture")
    }
}
