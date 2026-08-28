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

// MARK: - Synthesized identity
//
// Every loop in this file used to be `ForEach(Array(x.enumerated()),
// id: \.offset)`. Nothing in the payload carries an id: `LuminaBlock`,
// `LuminaSeries`, `LuminaChartPoint`, `LuminaKeyValue`, table rows and table
// cells are all plain values, and adding ids to them is a wire-schema change
// this repo does not own — the DTOs live in `LuminaVaultShared` and mirror the
// server's `openapi.yaml`.
//
// So identity is synthesized as **position + a hash of the content**:
//
//   * Position alone — the old scheme — is stable but says the wrong thing.
//     A job re-runs, block 0 goes from a stat card to a chart, and SwiftUI is
//     told it is the same row: it carries the previous view's state (an
//     in-flight `AsyncImage` download, a `Chart`'s animation) into unrelated
//     content.
//   * Content alone is right about change but is not unique. Rendered
//     documents repeat themselves constantly — "N/A" table cells, a flat
//     series where every y is 0 — and duplicate ids inside one `ForEach` are
//     undefined behaviour.
//
// The pair is always unique, because the position component alone already
// separates every element, and it changes exactly when the content does. A
// hash collision can therefore only produce spurious *continuity*; it can
// never produce a duplicate id.
//
// What goes into the content half is chosen per loop, not mechanically:
// where an element has a natural key it is used (`LuminaSeries.name` is the
// legend key, `LuminaChartPoint.x` is the category), and the top-level block
// hash deliberately covers what makes a block *a different thing* — its type,
// its subject, the shape of its collections — rather than every field that
// can change. A stat card whose value ticks from 41 to 42 is the same card
// with new data and should keep its view; a paragraph that becomes a table
// is not.

/// Identity for a `ForEach` element that has none of its own. File-private
/// on purpose: this is a local remedy for one id-less payload, not a token
/// the rest of the app should reach for.
private struct SynthesizedID: Hashable {
    let position: Int
    let content: Int
}

/// A payload element paired with its synthesized identity.
private struct IdentifiedElement<Value>: Identifiable {
    let id: SynthesizedID
    let value: Value
}

private extension Array {
    /// Pairs each element with `position + contentHash(element)`.
    func identified(by contentHash: (Element) -> Int) -> [IdentifiedElement<Element>] {
        enumerated().map { position, element in
            IdentifiedElement(
                id: SynthesizedID(position: position, content: contentHash(element)),
                value: element
            )
        }
    }
}

private extension Array where Element: Hashable {
    /// Pairs each element with `position + element.hashValue`. For payloads
    /// where the element *is* the content (a list item, a table cell, a whole
    /// table row).
    func identified() -> [IdentifiedElement<Element>] {
        identified(by: \.hashValue)
    }
}

/// Hash of the fields that decide *which* view a block is, and what it is
/// about. Deliberately excludes `value` / `delta` / `trend` and the contents
/// of the collections: those are the block's data, and data changing inside a
/// block of unchanged shape is precisely when view continuity is wanted.
private func blockContentHash(_ block: LuminaBlock) -> Int {
    var hasher = Hasher()
    hasher.combine(block.type)
    hasher.combine(block.level)
    hasher.combine(block.label)
    hasher.combine(block.text)
    hasher.combine(block.url)
    hasher.combine(block.items?.count)
    hasher.combine(block.columns)
    hasher.combine(block.rows?.count)
    hasher.combine(block.pairs?.count)
    hasher.combine(block.series?.map(\.name))
    return hasher.finalize()
}

private func keyValueContentHash(_ pair: LuminaKeyValue) -> Int {
    var hasher = Hasher()
    hasher.combine(pair.key)
    hasher.combine(pair.value)
    return hasher.finalize()
}

// MARK: - Renderer

struct BlockRenderer: View {
    let blocks: [LuminaBlock]

    var body: some View {
        // Lazy so a long job result doesn't build every block up front. The
        // host scroll view (`Features/Jobs/JobDetailView.swift`) is still an
        // eager `VStack`, so this only defers the blocks, not its siblings.
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(blocks.identified(by: blockContentHash)) { entry in
                BlockView(block: entry.value)
            }
        }
    }
}

private struct BlockView: View {
    @Environment(\.lvPalette) private var palette
    let block: LuminaBlock

    // Single dispatch — each helper is a small, independently type-checked expression.
    var body: some View {
        switch block.type {
        case "heading":          headingView
        case "paragraph",
             "markdown":         markdownView
        case "quote":            quoteView
        case "badge":            badgeView
        case "statCard":         StatCardBlock(block: block)
        case "lineChart",
             "barChart":         ChartBlock(block: block)
        case "list":             listView
        case "keyValue":         keyValueView
        case "table":            TableBlock(block: block)
        case "image":            imageView
        case "divider":          dividerView
        default:                 fallbackView
        }
    }

    // MARK: – Heading

    @ViewBuilder
    private var headingView: some View {
        let size = headingSize
        Text(block.text ?? "")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(palette.textPrimary)
    }

    private var headingSize: CGFloat {
        switch block.level ?? 2 {
        case 1:  return 22
        case 2:  return 18
        default: return 15
        }
    }

    // MARK: – Paragraph / Markdown

    @ViewBuilder
    private var markdownView: some View {
        markdownText(block.text ?? "")
    }

    @ViewBuilder
    private func markdownText(_ body: String) -> some View {
        if let attr = try? AttributedString(
            markdown: body,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attr)
                .font(.system(size: 15))
                .foregroundStyle(palette.textPrimary)
        } else {
            Text(body)
                .font(.system(size: 15))
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: – Quote

    @ViewBuilder
    private var quoteView: some View {
        let bar = Rectangle()
            .fill(palette.glowPrimary.opacity(0.6))
            .frame(width: 3)
        Text(block.text ?? "")
            .font(.system(size: 15, weight: .medium))
            .italic()
            .foregroundStyle(palette.textSecondary)
            .padding(.leading, 12)
            .overlay(alignment: .leading) { bar }
    }

    // MARK: – Badge

    @ViewBuilder
    private var badgeView: some View {
        let label = (block.text ?? "").uppercased()
        Text(label)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1)
            .foregroundStyle(palette.glowPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(palette.glowPrimary.opacity(0.12)))
            .overlay(Capsule().stroke(palette.glowPrimary.opacity(0.4), lineWidth: 1))
    }

    // MARK: – List

    @ViewBuilder
    private var listView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The item string *is* the content, so it is the content hash.
            ForEach((block.items ?? []).identified()) { entry in
                listItemRow(entry.value)
            }
        }
    }

    @ViewBuilder
    private func listItemRow(_ item: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(palette.glowPrimary)
                .frame(width: 5, height: 5)
                .padding(.top, 7)
            Text(item)
                .font(.system(size: 15))
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: – Key-Value

    @ViewBuilder
    private var keyValueView: some View {
        VStack(spacing: 6) {
            ForEach((block.pairs ?? []).identified(by: keyValueContentHash)) { entry in
                keyValueRow(entry.value)
            }
        }
    }

    @ViewBuilder
    private func keyValueRow(_ pair: LuminaKeyValue) -> some View {
        HStack {
            Text(pair.key)
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Text(pair.value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: – Image

    @ViewBuilder
    private var imageView: some View {
        if let urlString = block.url, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.surface.opacity(0.4))
                    .frame(height: 160)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: – Divider

    @ViewBuilder
    private var dividerView: some View {
        Divider().overlay(palette.textSecondary.opacity(0.3))
    }

    // MARK: – Fallback (unknown block type)

    @ViewBuilder
    private var fallbackView: some View {
        if let text = block.text { markdownText(text) }
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
                    .contentTransition(.numericText())
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
        .lvAnimation(LVMotion.standard, value: block.value)
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

    // Marks are extracted into @ChartContentBuilder helpers: the fully-inlined
    // Chart { ForEach { ForEach { if/else marks } } } expression times out the
    // Swift 6.2 type-checker ("unable to type-check in reasonable time").
    var body: some View {
        Chart {
            // A series' natural key is its legend name; a point's is its
            // x category. Both are paired with position so repeated names or
            // repeated categories still produce unique ids.
            ForEach((block.series ?? []).identified(by: { $0.name.hashValue })) { entry in
                seriesMarks(entry.value)
            }
        }
        .chartLegend(.visible)
        .frame(height: 200)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous).fill(palette.surface.opacity(0.4)))
    }

    @ChartContentBuilder
    private func seriesMarks(_ series: LuminaSeries) -> some ChartContent {
        ForEach(series.points.identified(by: { $0.x.hashValue })) { entry in
            if block.type == "barChart" {
                barMark(entry.value, seriesName: series.name)
            } else {
                lineMark(entry.value, seriesName: series.name)
            }
        }
    }

    private func barMark(_ point: LuminaChartPoint, seriesName: String) -> some ChartContent {
        BarMark(x: .value("x", point.x), y: .value("y", point.y))
            .foregroundStyle(by: .value("series", seriesName))
    }

    private func lineMark(_ point: LuminaChartPoint, seriesName: String) -> some ChartContent {
        LineMark(x: .value("x", point.x), y: .value("y", point.y))
            .foregroundStyle(by: .value("series", seriesName))
            .interpolationMethod(.catmullRom)
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
            // A row's content is the whole `[String]`; a cell's is its string.
            ForEach(rows.identified()) { entry in
                row(entry.value, header: false)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous).fill(palette.surface.opacity(0.4)))
    }

    private func row(_ cells: [String], header: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(cells.identified()) { entry in
                Text(entry.value)
                    .font(.system(size: 12, weight: header ? .bold : .regular))
                    .foregroundStyle(header ? palette.textPrimary : palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 5)
    }
}
