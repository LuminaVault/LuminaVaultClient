// LuminaVaultClient/LuminaVaultClient/Features/Think/Components/SourceLinkRow.swift
// HER-37: one row per QueryHit inside an InsightCard.
//
// A hit now carries a citation — the file it came from, the heading trail
// inside that file, and the exact line range. Showing it is the difference
// between "the model says so" and "open projects/hermes.md and read lines
// 40-58". Hits with no citation (memories captured through chat, direct API
// upserts) fall back to the snippet alone rather than inventing a location.
import LuminaVaultShared
import SwiftUI

struct SourceLinkRow: View {

    @Environment(\.lvPalette) private var palette

    let hit: QueryHitDTO

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LVIconView(.docText, size: 13, tint: palette.primary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(snippet)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)

                if let citation = hit.citation {
                    HStack(spacing: 4) {
                        Text(trail(for: citation))
                            .font(.system(size: 11))
                            .foregroundStyle(palette.primary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Text(lineRange(for: citation))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.lvTextMuted)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel(for: citation))
                } else if let createdAt = hit.createdAt {
                    Text(createdAt, style: .date)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.lvTextMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var snippet: String {
        let trimmed = hit.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(empty memory)" : trimmed
    }

    /// `hermes.md › Routing › Fallbacks`. The filename rather than the full
    /// path — the row is narrow, and the path is in the accessibility label.
    private func trail(for citation: MemoryCitationDTO) -> String {
        var parts: [String] = []
        if let path = citation.path {
            parts.append(path.split(separator: "/").last.map(String.init) ?? path)
        }
        parts.append(contentsOf: citation.headingPath)
        return parts.isEmpty ? "this memory" : parts.joined(separator: " › ")
    }

    private func lineRange(for citation: MemoryCitationDTO) -> String {
        citation.startLine == citation.endLine
            ? "L\(citation.startLine)"
            : "L\(citation.startLine)-\(citation.endLine)"
    }

    /// VoiceOver gets the full path — truncating it visually is a layout
    /// decision, not a reason to withhold where the answer came from.
    private func accessibilityLabel(for citation: MemoryCitationDTO) -> String {
        var parts: [String] = []
        if let path = citation.path { parts.append(path) }
        parts.append(contentsOf: citation.headingPath)
        let location = parts.joined(separator: ", ")
        let lines = citation.startLine == citation.endLine
            ? "line \(citation.startLine)"
            : "lines \(citation.startLine) to \(citation.endLine)"
        return location.isEmpty ? lines : "Source: \(location), \(lines)"
    }
}
