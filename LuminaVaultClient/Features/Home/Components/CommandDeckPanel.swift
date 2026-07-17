// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/CommandDeckPanel.swift
//
// Right-column Command Deck: numbered quick actions for the Home surface.

import SwiftUI

struct CommandDeckPanel<Content: View>: View {
    @Environment(\.lvPalette) private var palette

    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            Text("COMMAND DECK")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(palette.glowPrimary)

            content()
        }
        .padding(LVSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: 0.65)
    }
}

struct CommandDeckRow: View {
    @Environment(\.lvPalette) private var palette

    let title: String
    let number: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, LVSpacing.md)
        .padding(.vertical, LVSpacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: LVRadius.sm, style: .continuous)
                .fill(palette.surface.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LVRadius.sm, style: .continuous)
                .stroke(palette.glowPrimary.opacity(0.22), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}
