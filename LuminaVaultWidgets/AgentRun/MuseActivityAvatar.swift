//
//  MuseActivityAvatar.swift
//  LuminaVaultWidgets
//

import SwiftUI

/// The 110pt header avatar, shrunk: idle art plus the ring that carries the
/// working state (contract: "the ring carries the working state"). The ring
/// is a static stroke — a Live Activity cannot run an animation loop.
struct MuseActivityAvatar: View {
    let stage: AgentRunAttributes.ContentState.Stage
    let size: CGFloat
    var avatar: Image = Image("HermieAvatar")
    /// Read by VoiceOver where the avatar is the only thing shown (the
    /// minimal island). Elsewhere text beside it says the same, so it stays
    /// hidden.
    var spokenStatus: String?

    var body: some View {
        avatar
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(.circle)
            .padding(ringWidth + 1)
            .overlay { ring }
            .accessibilityHidden(spokenStatus == nil)
            .accessibilityLabel(spokenStatus ?? "")
    }

    private var ringWidth: CGFloat { max(1.5, size / 16) }

    @ViewBuilder private var ring: some View {
        switch stage {
        case .working:
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(MuseActivityPalette.accent, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        case .waiting:
            Circle().stroke(MuseActivityPalette.accent.opacity(0.9), lineWidth: ringWidth)
        case .done:
            Circle().stroke(MuseActivityPalette.accent.opacity(0.35), lineWidth: ringWidth)
        case .failed:
            Circle().stroke(MuseActivityPalette.snag.opacity(0.6), lineWidth: ringWidth)
        }
    }
}
