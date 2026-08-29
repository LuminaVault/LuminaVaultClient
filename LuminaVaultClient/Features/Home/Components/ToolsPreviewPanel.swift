// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/ToolsPreviewPanel.swift

import SwiftUI

struct ToolsPreviewPanel: View {
    @Environment(\.lvPalette) private var palette

    /// See `SkillsPreviewPanel` — a preview shows a glance, the header count
    /// and the overflow chip carry the total.
    private static let previewLimit = 3

    let tools: [String]
    let count: Int
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            HStack {
                Text("TOOLS")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(palette.glowPrimary)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }

            if isLoading {
                HStack {
                    Capsule().fill(Color.white.opacity(0.08)).frame(width: 56, height: 24)
                    Capsule().fill(Color.white.opacity(0.08)).frame(width: 72, height: 24)
                }
            } else if tools.isEmpty {
                Text("No extra tools installed yet.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            } else {
                // `LVFlowLayout`, not a `VStack`. The private helper this
                // replaced was named `FlexibleToolChips` but stacked
                // vertically, so every chip got its own row.
                LVFlowLayout(spacing: LVSpacing.sm) {
                    // Positional identity — see `SkillsPreviewPanel`. Tool
                    // names are server strings and are not guaranteed unique.
                    ForEach(Array(visibleTools.enumerated()), id: \.offset) { _, name in
                        chip(name, muted: false)
                    }
                    if overflow > 0 {
                        chip("+\(overflow) more", muted: true)
                    }
                }
            }
        }
        .padding(LVSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: 0.65)
    }

    private func chip(_ text: String, muted: Bool) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(muted ? palette.textSecondary : palette.glowPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    muted
                        ? palette.textSecondary.opacity(0.08)
                        : palette.glowPrimary.opacity(0.12)
                )
            )
            .overlay(
                Capsule().stroke(
                    muted
                        ? palette.textSecondary.opacity(0.25)
                        : palette.glowPrimary.opacity(0.3),
                    lineWidth: 1
                )
            )
    }

    private var visibleTools: [String] {
        Array(tools.prefix(Self.previewLimit))
    }

    private var overflow: Int {
        max(0, max(count, tools.count) - visibleTools.count)
    }
}
