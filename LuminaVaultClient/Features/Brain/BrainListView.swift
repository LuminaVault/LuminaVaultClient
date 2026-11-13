// The visible notes and memories as a list: the VoiceOver and Switch Control
// path through the graph, which never needs the canvas. Heaviest first,
// searchable; a row toggles that point in the selection (additively, as a long
// press on the canvas does) and carries the `.isSelected` trait.

import LuminaVaultShared
import SwiftUI

struct BrainListView: View {
    let visible: VisibleBrainGraph?
    let vaults: [BrainGraphVaultDTO]
    let selection: BrainSelection

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lvPalette) private var palette
    @State private var query = ""

    var body: some View {
        let rows = visible.map { BrainTabState.listRows($0, vaults: vaults, query: query) } ?? []
        let selected = Set(selection.selected)
        NavigationStack {
            List(rows) { row in
                BrainListRowView(row: row, isSelected: selected.contains(row.id)) {
                    selection.click(row.id, additive: true)
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if rows.isEmpty {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView(BrainTabState.listEmptyText, systemImage: "circle.dashed")
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .navigationTitle("Notes and memories")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: BrainTabState.searchPrompt)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("brain.sheet.done")
                }
            }
        }
    }
}

private struct BrainListRowView: View {
    @Environment(\.lvPalette) private var palette

    let row: BrainListRow
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: LVSpacing.md) {
                VStack(alignment: .leading, spacing: LVSpacing.hairline) {
                    Text(row.label)
                        .foregroundStyle(palette.textPrimary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: LVSpacing.sm)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.primary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("brain.list.row.\(row.id)")
    }

    private var detail: String {
        [row.kind, row.vault, BrainTabState.connectionsText(row.connections)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
