// LuminaVaultClient/LuminaVaultClient/Features/Think/Memo/Components/MemoRowView.swift
// HER-37: list cell for a single saved memo.
import SwiftUI

struct MemoRowView: View {

    @Environment(\.lvPalette) private var palette

    let memo: MemoSummaryDTO

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(palette.accent)
                .font(.system(size: 14))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(memo.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                Text(memo.createdAt, style: .date)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.lvTextMuted)
                if let summary = memo.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .lvGlassCard(cornerRadius: 14, intensity: 0.4)
    }
}
