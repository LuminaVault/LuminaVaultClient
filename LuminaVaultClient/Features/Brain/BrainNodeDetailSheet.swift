// LuminaVaultClient/LuminaVaultClient/Features/Brain/BrainNodeDetailSheet.swift
//
// HER-235 — detail sheet for a tapped graph node, kind-aware (memory vs
// wiki page). v1 shows title, tags, and timestamp. A follow-up can route a
// wiki node to its full markdown page once the node DTO carries the vault
// path, and a memory node to `MemoEditorView`.

import LuminaVaultShared
import SwiftUI

struct BrainNodeDetailSheet: View {

    @Environment(\.lvPalette) private var palette

    let node: MemoryGraphNodeDTO

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        LVIconView(kindIcon, size: 13, tint: accentColor)
                        Text(kindLabel.uppercased())
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(accentColor)
                    }

                    Text(node.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)

                    HStack(spacing: 8) {
                        LVIconView(.clock, size: 13, tint: palette.textSecondary)
                        Text(node.createdAt, style: .date)
                    }
                    .font(.footnote)
                    .foregroundStyle(palette.textSecondary)

                    if !node.tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(node.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(accentColor.opacity(0.15))
                                    .foregroundStyle(accentColor)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    // Score is a memory-only signal; wiki pages render at a
                    // constant size so it carries no meaning for them.
                    if node.kind == .memory {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Score")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.lvTextMuted)
                            Text(String(format: "%.2f", node.score))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(palette.textPrimary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .lvBackground()
            .navigationTitle(kindLabel)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Kind presentation

    private var kindLabel: String {
        node.kind == .wikiPage ? "Wiki Page" : "Memory"
    }

    private var kindIcon: LVIcon {
        node.kind == .wikiPage ? .docText : .brain
    }

    /// Wiki pages ride the warm channel (gold accent) to match the graph;
    /// memories ride the cool channel (cyan primary).
    private var accentColor: Color {
        node.kind == .wikiPage ? palette.accent : palette.primary
    }
}

/// Local tag-list flow layout. SwiftUI's stock `Layout` makes a 10-line
/// wrap layout trivial; pulling in another component would be overkill.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, in: width)
        let height = rows.reduce(0) { $0 + $1.height + spacing } - spacing
        return CGSize(width: width, height: max(0, height))
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let rows = arrange(subviews: subviews, in: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for (subview, size) in row.items {
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(Subviews.Element, CGSize)] = []
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        var x: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
                x = 0
            }
            rows[rows.count - 1].items.append((sub, size))
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            x += size.width + spacing
        }
        return rows
    }
}
