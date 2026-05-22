// LuminaVaultClient/LuminaVaultClient/Features/Think/Components/SuggestionChipsRow.swift
// HER-37: horizontally scrolling chips of context-aware query suggestions.
import SwiftUI

struct SuggestionChipsRow: View {

    @Environment(\.lvPalette) private var palette

    let suggestions: [String]
    var onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        onTap(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(Color.lvGlass)
                            )
                            .overlay(
                                Capsule().stroke(palette.surfaceStroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
