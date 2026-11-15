// LuminaVaultClient/LuminaVaultClient/Features/Vault/NoteLinksSection.swift
// Backlog E2.2: "Linked from / Links to" under a note in the reader. Tapping a
// row opens that note; links to notes not written yet are listed, muted.
import SwiftUI

struct NoteLinksSection: View {
    @Environment(\.lvPalette) private var palette

    let groups: NoteLinkGroups?
    let isLoading: Bool
    let error: String?
    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider().background(palette.surfaceStroke)

            if isLoading, groups == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(palette.textSecondary)
            } else if let groups {
                if groups.isEmpty {
                    Text("No links yet. Write [[Another note]] to connect notes.")
                        .font(.footnote)
                        .foregroundStyle(palette.textSecondary)
                } else {
                    list("Linked from", rows: groups.linkedFrom, empty: "No notes link here yet.")
                    list("Links to", rows: groups.linksTo, empty: "This note links to no other notes.")
                    if !groups.unresolved.isEmpty {
                        list("Not written yet", rows: groups.unresolved, empty: "")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func list(_ title: String, rows: [NoteLinkGroups.Row], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) · \(rows.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .accessibilityAddTraits(.isHeader)

            if rows.isEmpty {
                Text(empty)
                    .font(.footnote)
                    .foregroundStyle(palette.textSecondary.opacity(0.8))
            } else {
                ForEach(rows) { row in
                    if let path = row.path {
                        Button {
                            onOpen(path)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                    .font(.caption)
                                    .foregroundStyle(palette.glowPrimary)
                                Text(path)
                                    .font(.subheadline)
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if row.count > 1 {
                                    Text("×\(row.count)")
                                        .font(.caption)
                                        .foregroundStyle(palette.textSecondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(palette.textSecondary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(palette.surface))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(path)")
                    } else {
                        Text("[[\(row.label)]]")
                            .font(.subheadline)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .accessibilityLabel("\(row.label), not written yet")
                    }
                }
            }
        }
    }
}
