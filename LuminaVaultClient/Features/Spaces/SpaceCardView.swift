// LuminaVaultClient/LuminaVaultClient/Features/Spaces/SpaceCardView.swift
// HER-35: tile rendered in the LazyVGrid on the Spaces home. Long-press
// context menu fires the rename / change-icon / change-color / delete
// flows owned by SpacesListView.
import SwiftUI

struct SpaceCardView: View {

    @Environment(\.lvPalette) private var palette

    let space: SpaceDTO
    let onEdit: () -> Void
    let onDelete: () -> Void

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: space.icon ?? "folder.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(palette.primary)
                Spacer()
                Menu {
                    Button("Edit", action: onEdit)
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .contentShape(Rectangle())
                }
            }

            Text(space.name)
                .font(.system(size: 16, weight: .heavy))
                .lineLimit(1)

            Text("\(space.noteCount) \(space.noteCount == 1 ? "note" : "notes")")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            if let lastCompiledAt = space.lastCompiledAt {
                Text("compiled \(Self.relativeFormatter.localizedString(for: lastCompiledAt, relativeTo: Date()))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .lvGlassCard(cornerRadius: 16, intensity: 0.5)
    }
}
