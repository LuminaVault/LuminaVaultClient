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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                // HER-291: kept as Image — runtime symbol name
                Image(systemName: space.icon ?? "folder.fill")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(palette.glowPrimary)
                    .shadow(color: palette.glowPrimary.opacity(0.6), radius: 8)
                
                Spacer()
                
                Menu {
                    Button("Edit", action: onEdit)
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    LVIconView(.ellipsis, size: 14, tint: palette.textSecondary.opacity(0.5), weight: .bold)
                        .padding(8)
                        .contentShape(Rectangle())
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(space.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)

                Text("\(space.noteCount) \(space.noteCount == 1 ? "note" : "notes")")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.glowPrimary)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .lvGlassCard(cornerRadius: 24, intensity: 0.7)
    }
}
