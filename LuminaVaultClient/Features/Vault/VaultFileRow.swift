// LuminaVaultClient/LuminaVaultClient/Features/Vault/VaultFileRow.swift
// One row of the vault, wherever the vault is being listed.
//
// Extracted from `VaultFilesListView.fileRow(_:)` when the capture home grew a
// recent-saves feed. Two surfaces drawing the same row from two copies is how
// they end up disagreeing about what a todo or an untitled note looks like.
//
// What the row *says* — title, subtitle, glyph — is `VaultFileDisplay`'s job.
// This is only how it is laid out.
import SwiftUI
import LuminaVaultShared

struct VaultFileRow: View {
    let file: VaultFileDTO
    /// The Space this file lives in, when the host knows it. A path told the
    /// user nothing; the name of the place they filed it tells them something.
    var spaceName: String?

    var body: some View {
        let meta = file.metadata
        let isTodo = meta?.isTodo == true
        let done = meta?.done == true
        let subtitle = VaultFileDisplay.subtitle(for: file, spaceName: spaceName)

        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: isTodo
                ? (done ? "checkmark.circle.fill" : "circle")
                : VaultFileDisplay.symbolName(for: file))
                .font(.body)
                .foregroundStyle(isTodo ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(VaultFileDisplay.title(for: file))
                    .font(.body)
                    .strikethrough(done, color: .secondary)
                    .lineLimit(2)

                if let due = meta?.dueAt {
                    Label(due.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .font(.footnote)
                        .foregroundStyle(.tint)
                } else if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
