// LuminaVaultClient/LuminaVaultClient/Components/BlockRenderer.swift
//
// Lumina Jobs P2 — renders a `[LuminaBlock]` payload as native SwiftUI
// (cards, charts, lists) instead of Markdown. Domain-agnostic: the AI picks
// which blocks to emit; this maps each to a view. Unknown block types render
// nothing (graceful fallback) so newer server blocks never break this client.
// Reusable beyond jobs — note bodies + link summaries can render the same way.

import Charts
import LuminaVaultShared
import SwiftUI

struct BlockRenderer: View {
    let blocks: [LuminaBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
    }
}

private struct BlockView: View {
    @Environment(\.lvPalette) private var palette
    let block: LuminaBlock

    var body: some View {
        switch block.type {
        case "heading":
            Text(block.text ?? "")
                .font(.system(size: headingSize, weight: .bold))
                .foregroundStyle(palette.textPrimary)

        case "paragraph", "markdown":
            markdownText(block.text ?? "")

        case "quote":
            Text(block.text ?? "")
                .font(.system(size: 15, weight: .medium))
                .italic()
                .foregroundStyle(palette.textSecondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(palette.glowPrimary.opacity(0.6)).frame(width: 3)
                }

        case "badge":
            Text((block.text ?? "").uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(palette.glowPrimary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(palette.glowPrimary.opacity(0.12)))
                .overlay(Capsule().stroke(palette.glowPrimary.opacity(0.4), lineWidth: 1))

        case "statCard":
            StatCardBlock(block: block)

        case "lineChart", "barChart":
            ChartBlock(block: block)

        case "list":
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array((block.items ?? []).enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(palette.glowPrimary).frame(width: 5, height: 5).padding(.top, 7)
                        Text(item).font(.system(size: 15)).foregroundStyle(palette.textPrimary)
                    }
                }
            }

        case "keyValue":
            VStack(spacing: 6) {
                ForEach(Array((block.pairs ?? []).enumerated()), id: \.offset) { _, pair in
                    HStack {
                        Text(pair.key).font(.system(size: 13)).foregroundStyle(palette.textSecondary)
                        Spacer()
                        Text(pair.value).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    }
                }
            }

        case "table":
            TableBlock(block: block)

        case "image":
            if let urlString = block.url, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12).fill(palette.surface.opacity(0.4)).frame(height: 160)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

        case "divider":
            Divider().overlay(palette.textSecondary.opacity(0.3))

        default:
            // Unknown block type — render its text if any, else skip.
            if let text = block.text { markdownText(text) }
        }
    }

    private var headingSize: CGFloat {
        switch block.level ?? 2 {
        case 1: return 22
        case 2: return 18
        default: return 15
        }
    }

    @ViewBuilder
    private func markdownText(_ body: String) -> some View {
        if let attr = try? AttributedString(
            markdown: body,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attr).font(.system(size: 15)).foregroundStyle(palette.textPrimary)
        } else {
            Text(body).font(.system(size: 15)).foregroundStyle(palette.textPrimary)
        }
    }
}

// MARK: - Stat card

private struct StatCardBlock: View {
    @Environment(\.lvPalette) private var palette
    let block: LuminaBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label = block.label {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(1)
                    .foregroundStyle(palette.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(block.value ?? "—")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                if let delta = block.delta {
                    Text(delta)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(trendColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous).fill(palette.surface.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous).stroke(trendColor.opacity(0.3), lineWidth: 1))
    }

    private var trendColor: Color {
        switch block.trend {
        case "up": return palette.primary
        case "down": return .red
        default: return palette.textSecondary
        }
    }
}

// MARK: - Chart

private struct ChartBlock: View {
    @Environment(\.lvPalette) private var palette
    let block: LuminaBlock

    var body: some View {
        Chart {
            ForEach(Array((block.series ?? []).enumerated()), id: \.offset) { _, series in
                ForEach(Array(series.points.enumerated()), id: \.offset) { _, point in
                    if block.type == "barChart" {
                        BarMark(x: .value("x", point.x), y: .value("y", point.y))
                            .foregroundStyle(by: .value("series", series.name))
                    } else {
                        LineMark(x: .value("x", point.x), y: .value("y", point.y))
                            .foregroundStyle(by: .value("series", series.name))
                            .interpolationMethod(.catmullRom)
                    }
                }
            }
        }
        .chartLegend(.visible)
        .frame(height: 200)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous).fill(palette.surface.opacity(0.4)))
    }
}

// MARK: - Table

private struct TableBlock: View {
    @Environment(\.lvPalette) private var palette
    let block: LuminaBlock

    var body: some View {
        let columns = block.columns ?? []
        let rows = block.rows ?? []
        VStack(spacing: 0) {
            if !columns.isEmpty {
                row(columns, header: true)
                Divider().overlay(palette.textSecondary.opacity(0.3))
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                row(r, header: false)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous).fill(palette.surface.opacity(0.4)))
    }

    private func row(_ cells: [String], header: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell)
                    .font(.system(size: 12, weight: header ? .bold : .regular))
                    .foregroundStyle(header ? palette.textPrimary : palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 5)
    }
}
