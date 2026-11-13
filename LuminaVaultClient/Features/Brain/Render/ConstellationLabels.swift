// The Constellation's labels: how many a view carries, which stars get one
// (selected, then lit, then the heaviest) and where each plate goes, clear of
// the selection rings and of each other. Pure; a port of the web app's
// `render-3d-labels.ts`, placing with the 2D canvas's `BrainLabelBoxes`.

import CoreGraphics
import Foundation

/// One placed label: its star and its plate, both in screen points.
nonisolated struct ConstellationLabel: Equatable, Sendable, Identifiable {
    var star: Int
    var text: String
    var rect: CGRect
    var selected: Bool
    var id: Int { star }
}

nonisolated extension ConstellationRules {
    /// How many labels a view of this size can carry without crowding: 8 to 24.
    static func labelQuota(_ size: CGSize, max top: Int = maxLabels) -> Int {
        max(8, min(top, Int((size.width * size.height / 14000).rounded())))
    }

    /// Stars to offer a label, best first: by tier (selected, lit, other).
    /// Inside the selected and lit tiers the nearest comes first; inside the
    /// resting tier the heaviest does, nearness breaking ties. Hidden stars,
    /// stars behind the camera and stars off the view are left out.
    static func rankLabels(_ p: ConstellationProjection, tiers: [ConstellationTier], weights: [Double]) -> [Int] {
        let w = p.size.width, h = p.size.height
        let shown = (0 ..< p.count).filter { i in
            tiers[i] != .hidden && p.x[i] >= 0 && p.x[i] <= w && p.y[i] >= 0 && p.y[i] <= h
        }
        return shown.sorted { a, b in
            if tiers[a] != tiers[b] { return tiers[a] < tiers[b] }
            if tiers[a] == .other, weights[a] != weights[b] { return weights[a] > weights[b] }
            if p.depth[a] != p.depth[b] { return p.depth[a] < p.depth[b] }
            return a < b
        }
    }

    /// How far a selected star's ring reaches on screen, in points.
    static func selectionReach(_ starRadius: CGFloat) -> CGFloat {
        max(ringRadius, starRadius * ringToStar)
    }

    /// Chooses and places up to 24 labels (fewer in a small view): selected
    /// first, then lit, then the heaviest. Selection rings claim their space
    /// first, so no label covers one; in a small graph every star does, as the
    /// 2D view keeps labels off points. A lower-ranked label that would
    /// collide is dropped; a selected one is always placed, slid onto the view.
    static func placeLabels(
        _ p: ConstellationProjection,
        tiers: [ConstellationTier],
        weights: [Double],
        texts: [String],
        textSize: (String) -> CGSize
    ) -> [ConstellationLabel] {
        guard !p.x.isEmpty, p.size.width > 0, p.size.height > 0 else { return [] }
        let ranked = rankLabels(p, tiers: tiers, weights: weights)
        var boxes = BrainLabelBoxes(canvas: p.size)
        let everyStar = p.count <= BrainGraphCanvasLogic.smallGraph
        for i in ranked {
            let selected = tiers[i] == .selected
            if !selected, !everyStar { break }
            let half = selected ? selectionReach(p.radius[i]) + 1 : p.radius[i] * labelClear + 1
            boxes.occupy(CGRect(x: p.x[i] - half, y: p.y[i] - half, width: half * 2, height: half * 2))
        }
        let quota = labelQuota(p.size)
        var out: [ConstellationLabel] = []
        for i in ranked where out.count < quota {
            let selected = tiers[i] == .selected
            let reach = (selected ? selectionReach(p.radius[i]) : p.radius[i] * labelClear) + 2
            let size = textSize(texts[i])
            let spots = BrainGraphCanvasLogic.labelSpots(centre: p.point(i), radius: reach, text: size)
            guard let spot = boxes.place(spots, canvas: p.size, force: selected) else { continue }
            out.append(ConstellationLabel(star: i, text: texts[i], rect: spot.rect, selected: selected))
        }
        return out
    }
}
