// LuminaVaultClient/LuminaVaultClient/Components/LVChipGrid.swift
//
// HER-100 — flexible chip-grid layout used by the SOUL.md quiz steps.
// Wraps content into `columns` evenly-sized columns; rows expand as
// needed. Items must be `Identifiable` so SwiftUI can diff cleanly
// when the underlying source mutates.

import SwiftUI

struct LVChipGrid<Item: Identifiable, ChipView: View>: View {
    let items: [Item]
    var columns: Int = 2
    var spacing: CGFloat = 10
    @ViewBuilder let chip: (Item) -> ChipView

    var body: some View {
        let layout = Array(
            repeating: GridItem(.flexible(), spacing: spacing),
            count: max(1, columns)
        )
        LazyVGrid(columns: layout, spacing: spacing) {
            ForEach(items) { item in
                chip(item)
            }
        }
    }
}
