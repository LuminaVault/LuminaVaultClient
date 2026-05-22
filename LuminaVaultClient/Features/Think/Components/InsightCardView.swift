// LuminaVaultClient/LuminaVaultClient/Features/Think/Components/InsightCardView.swift
// HER-37: insight card replacing the chat-bubble metaphor. Summary +
// source provenance + "Save as Memo" CTA + follow-up chips.
//
// Personality strings ("As you usually prefer concise insights…") are
// deliberately absent at scaffold — they depend on HER-100 SOUL.md.
import SwiftUI

struct InsightCardView: View {

    @Environment(\.lvPalette) private var palette

    let response: QueryResponse
    let queryText: String
    let followUps: [String]
    var onSaveAsMemo: () -> Void
    var onFollowUp: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(response.summary)
                .font(.system(size: 15))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !response.hits.isEmpty {
                Divider().overlay(palette.surfaceStroke)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(response.hits) { hit in
                        SourceLinkRow(hit: hit)
                    }
                }
            }

            HStack(spacing: 10) {
                Button(action: onSaveAsMemo) {
                    Label("Save as Memo", systemImage: "bookmark.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(palette.accent.opacity(0.15))
                        )
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
                Spacer()
            }

            if !followUps.isEmpty {
                FollowUpChipsView(chips: followUps, onTap: onFollowUp)
            }
        }
        .padding(16)
        .lvGlassCard(cornerRadius: 18, intensity: 0.55)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(queryText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
            Text(provenance)
                .font(.system(size: 11))
                .foregroundStyle(Color.lvTextMuted)
        }
    }

    private var provenance: String {
        let count = response.hits.count
        switch count {
        case 0: return "Synthesized without source memories."
        case 1: return "Based on 1 memory from your vault."
        default: return "Based on \(count) memories from your vault."
        }
    }
}
