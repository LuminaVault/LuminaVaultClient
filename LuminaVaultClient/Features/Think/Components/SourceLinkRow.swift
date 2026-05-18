// LuminaVaultClient/LuminaVaultClient/Features/Think/Components/SourceLinkRow.swift
// HER-37: one row per QueryHit inside an InsightCard. Tap → open the
// referenced vault file (wire-up to the existing Reader is a follow-up).
import SwiftUI

struct SourceLinkRow: View {
    let hit: QueryHitDTO

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 13))
                .foregroundStyle(Color.lvCyan)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.lvTextPrimary)
                    .lineLimit(2)
                if let createdAt = hit.createdAt {
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
}
