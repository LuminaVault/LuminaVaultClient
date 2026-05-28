// LuminaVaultClient/LuminaVaultClient/Features/Today/Components/TodayCardView.swift
//
// HER-177 — single card variant. Renders headline + 2-line body
// + tap to open the linked memo/memory/vault file. Highlight border
// flips on when an APNS digest deep-links this output.

import LuminaVaultShared
import SwiftUI

struct TodayCardView: View {

    @Environment(\.lvPalette) private var palette

    let output: SkillOutputDTO
    let highlighted: Bool
    let onTap: () -> Void
    let onShare: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    // HER-291: kept as Image — runtime symbol name
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(badge.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(tint)
                    Spacer()
                    Button(action: onShare) {
                        LVIconView(.squareAndArrowUp, size: 14, tint: palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                Text(output.headline)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.leading)
                Text(output.body.prefix(140) + (output.body.count > 140 ? "…" : ""))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lvGlassCard(cornerRadius: 16, intensity: highlighted ? 0.9 : 0.5)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(highlighted ? palette.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .lvGlowPress()
    }

    private var icon: String {
        switch output.kind {
        case .dailyBrief: "sun.max.fill"
        case .weeklyMemo: "doc.text.fill"
        case .correlationInsight: "chart.line.uptrend.xyaxis"
        case .captureEnriched: "sparkle.magnifyingglass"
        case .patternFinding: "circle.hexagongrid.fill"
        case .contradictionFinding: "exclamationmark.triangle.fill"
        case .generic: "bubble.left.fill"
        }
    }

    private var badge: String {
        switch output.kind {
        case .dailyBrief: "Daily brief"
        case .weeklyMemo: "Weekly memo"
        case .correlationInsight: "Correlation"
        case .captureEnriched: "Capture"
        case .patternFinding: "Pattern"
        case .contradictionFinding: "Contradiction"
        case .generic: output.skillName
        }
    }

    private var tint: Color {
        switch output.kind {
        case .contradictionFinding: .red
        case .patternFinding, .correlationInsight: palette.accent
        default: palette.primary
        }
    }
}
