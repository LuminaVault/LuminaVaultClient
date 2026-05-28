// LuminaVaultClient/LuminaVaultClient/Features/Think/Memo/Components/LuminaSuggestionsSidebar.swift
// HER-37: empty-state shell for the "Lumina thinks you should include…"
// sidebar described in the Linear ticket. Real suggestions land in
// HER-37b when the server-side memo planner exposes inline hints.
import SwiftUI

struct LuminaSuggestionsSidebar: View {

    @Environment(\.lvPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                LVIconView(.sparkles, tint: palette.accent)
                Text("Lumina's Suggestions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            Text("Suggestions tied to your vault and SOUL.md appear here once the memo planner is wired up.")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.lvGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
    }
}
