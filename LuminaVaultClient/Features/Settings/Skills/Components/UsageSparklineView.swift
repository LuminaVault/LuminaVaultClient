// LuminaVaultClient/LuminaVaultClient/Features/Settings/Skills/Components/UsageSparklineView.swift
//
// HER-247 — pure SwiftUI 14-day bar chart. No external dependency.
// Server returns oldest-first; we render left-to-right.

import LuminaVaultShared
import SwiftUI

struct UsageSparklineView: View {

    @Environment(\.lvPalette) private var palette

    let points: [SkillSparklinePoint]

    var body: some View {
        GeometryReader { proxy in
            let maxCount = max(points.map(\.count).max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    let height = max(2, proxy.size.height * CGFloat(point.count) / CGFloat(maxCount))
                    Capsule()
                        .fill(point.count > 0 ? palette.primary : palette.primary.opacity(0.18))
                        .frame(height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 40)
        .accessibilityElement()
        .accessibilityLabel(accessibility)
    }

    private var accessibility: String {
        let total = points.reduce(0) { $0 + $1.count }
        let peak = points.max(by: { $0.count < $1.count })
        if let peak {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "14-day usage: \(total) runs total, peak \(peak.count) on \(formatter.string(from: peak.day))."
        }
        return "14-day usage: no runs recorded."
    }
}
