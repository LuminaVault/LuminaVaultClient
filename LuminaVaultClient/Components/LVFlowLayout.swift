// LuminaVaultClient/LuminaVaultClient/Components/LVFlowLayout.swift
//
// Wrapping layout for variable-width content — chips, tags, tokens. Places
// subviews left to right and breaks to a new row when the next one would
// overflow the proposed width.
//
// `LVChipGrid` is the fixed-column `LazyVGrid` sibling: use that when every
// item should occupy an equal share of the width, and this when the items
// size themselves and should pack.
//
// Lifted out of `SkillsPreviewPanel`, which held the original private copy.
// `BrainNodeDetailSheet` and `WikilinkMarkdownView` still carry their own
// private duplicates; they can adopt this and drop them.

import SwiftUI

struct LVFlowLayout: Layout {
    // Literal, not `LVSpacing.sm`: the spacing tokens are MainActor-isolated
    // and `Layout` conformance is nonisolated, so a token default here is
    // "main actor-isolated default value in a nonisolated context" — a
    // warning today and an error under the Swift 6 language mode. Call
    // sites pass the token explicitly instead.
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
