// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/SkillsPreviewPanel.swift

import SwiftUI

struct SkillsPreviewPanel: View {
    @Environment(\.lvPalette) private var palette

    /// A preview panel shows a glance, not an inventory. The server returns
    /// the full list; the header count and the overflow chip carry "how many",
    /// so the body only ever renders this many.
    private static let previewLimit = 3

    let skills: [String]
    let skillsCount: Int?
    let isLoading: Bool
    var onSeeAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            HStack {
                Text("SKILLS")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(palette.glowPrimary)
                Spacer()
                if let skillsCount {
                    Text("\(skillsCount)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                }
                if let onSeeAll {
                    Button("See all", action: onSeeAll)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.glowPrimary)
                }
            }

            if isLoading {
                FlowPlaceholder()
            } else if skills.isEmpty {
                Text("No skills yet — create one.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.vertical, LVSpacing.sm)
            } else {
                LVFlowLayout(spacing: LVSpacing.sm) {
                    // Positional identity, not `id: \.self`. These are server
                    // strings: two skills sharing a name (or a name being
                    // edited) gave `ForEach` duplicate ids, which is undefined
                    // behaviour, and any rename re-created every chip after it.
                    ForEach(Array(visibleSkills.enumerated()), id: \.offset) { _, name in
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
            .foregroundStyle(muted ? palette.textSecondary : palette.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
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
                        : palette.glowPrimary.opacity(0.35),
                    lineWidth: 1
                )
            )
    }

    private var visibleSkills: [String] {
        Array(skills.prefix(Self.previewLimit))
    }

    /// Counts against the server total when it is known — the array can be a
    /// truncated payload, in which case `skills.count` understates the overflow.
    private var overflow: Int {
        max(0, max(skillsCount ?? skills.count, skills.count) - visibleSkills.count)
    }
}

private struct FlowPlaceholder: View {
    @Environment(\.lvPalette) private var palette
    var body: some View {
        HStack {
            ForEach(0..<3, id: \.self) { _ in
                Capsule()
                    .fill(palette.surface.opacity(0.5))
                    .frame(width: 64, height: 28)
            }
        }
        .redacted(reason: .placeholder)
    }
}
