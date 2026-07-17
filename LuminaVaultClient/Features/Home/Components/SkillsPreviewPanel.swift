// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/SkillsPreviewPanel.swift

import SwiftUI

struct SkillsPreviewPanel: View {
    @Environment(\.lvPalette) private var palette

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
                FlowLayout(spacing: 8) {
                    ForEach(skills, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(palette.glowPrimary.opacity(0.12))
                            )
                            .overlay(
                                Capsule().stroke(palette.glowPrimary.opacity(0.35), lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(LVSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: 0.65)
    }
}

// Minimal wrapping layout for skill chips without pulling a heavy dependency.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var height: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            height = y + rowHeight
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
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
