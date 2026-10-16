// LuminaVaultClient/LuminaVaultClient/Features/Recap/Period/PeriodRecapShareCard.swift
//
// The 9:16 image a year / month in review shares. Numbers, the period and
// the persona only — never a tag, title, Space name or the model's themes —
// so it is as safe to post as `shareText`.

import LuminaVaultShared
import SwiftUI
import UIKit

struct PeriodRecapShareCard: View {
    let recap: PeriodRecapResponse

    /// 360 × 640 pt, rendered at 3× → 1080 × 1920 px.
    static let size = CGSize(width: 360, height: 640)

    @Environment(\.lvPalette) private var palette

    var body: some View {
        let stats = PeriodRecapDeck.shareStats(recap)
        let span = recap.period == .month ? "month" : "year"
        VStack(alignment: .leading, spacing: 18) {
            Spacer().frame(height: 60)
            Text((recap.isComplete ? "My \(span) in review" : "My \(span) so far").uppercased())
                .font(.system(size: 14, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(palette.textSecondary)
            Text(PeriodRecapDeck.periodName(recap))
                .font(.system(size: recap.period == .month ? 46 : 72, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(2)
                .foregroundStyle(palette.textPrimary)
            Spacer().frame(height: 12)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 22) {
                ForEach(Array(stats.enumerated()), id: \.offset) { i, stat in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.value)
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(i == 0 ? palette.primary : palette.textPrimary)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(stat.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            Spacer()
            Text(PeriodRecapDeck.persona(recap.rhythm?.persona).title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(palette.accent)
            Text("luminavault.fyi")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.textSecondary)
            Spacer().frame(height: 28)
        }
        .padding(.horizontal, 36)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .leading)
        .background {
            ZStack {
                palette.backgroundBase
                RadialGradient(colors: [palette.primary.opacity(0.45), .clear], center: .topLeading, startRadius: 0, endRadius: 320)
                RadialGradient(colors: [palette.secondary.opacity(0.45), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 360)
                RadialGradient(colors: [palette.accent.opacity(0.3), .clear], center: .init(x: 0.85, y: 0.2), startRadius: 0, endRadius: 180)
            }
        }
    }

    /// The card as an image at 3×. Main-actor because `ImageRenderer` is.
    @MainActor
    static func render(_ recap: PeriodRecapResponse, palette: LVPalette) -> UIImage? {
        let renderer = ImageRenderer(
            content: PeriodRecapShareCard(recap: recap)
                .environment(\.lvPalette, palette)
                .environment(\.lvAmbientMotionEnabled, false)
        )
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.uiImage
    }
}
