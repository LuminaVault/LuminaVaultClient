// LuminaVaultClient/LuminaVaultClient/Features/Shell/AgentWorkingBanner.swift
//
// "An agent is still working" — shown on every tab but AI while a run is in
// flight, and absent the rest of the time. A banner that is always there
// teaches people to ignore it; its presence is the signal.

import SwiftUI

struct AgentWorkingBanner: View {
    @Environment(\.lvPalette) private var palette

    let count: Int
    let onOpen: () -> Void

    private var title: String {
        count == 1 ? "Agent working" : "\(count) agents working"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: LVSpacing.sm) {
                ProgressView().controlSize(.mini)
                Text(title)
                    .lvFont(.microTag)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Text("Open")
                    .lvFont(.microTag)
                    .foregroundStyle(palette.accent)
            }
            .padding(.horizontal, LVSpacing.lg)
            .frame(minHeight: 44)
            .background(palette.surface)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint("Opens the AI tab")
    }
}
