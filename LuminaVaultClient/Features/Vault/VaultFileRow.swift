// LuminaVaultClient/LuminaVaultClient/Features/Vault/VaultFileRow.swift
// One row of the vault, wherever the vault is being listed.
//
// Extracted from `VaultFilesListView.fileRow(_:)` when the capture home grew a
// recent-saves feed. Two surfaces drawing the same row from two copies is how
// they end up disagreeing about what a todo or an untitled note looks like.
import SwiftUI
import LuminaVaultShared

struct VaultFileRow: View {
    let file: VaultFileDTO

    @Environment(\.lvPalette) private var palette

    /// Hoisted because the row builder runs for every row on every body pass,
    /// and `ByteCountFormatter.string(fromByteCount:)` builds and discards a
    /// formatter on each call.
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    /// A file's own title if it has one, otherwise its filename. A captured
    /// link has no title until enrichment rewrites the file, so its filename —
    /// `<stamp>-<host>-<uuid8>.md` — is what the user sees in the meantime.
    private var title: String {
        file.metadata?.title.flatMap { $0.isEmpty ? nil : $0 }
            ?? (file.path as NSString).lastPathComponent
    }

    var body: some View {
        let meta = file.metadata
        let isTodo = meta?.isTodo == true
        let done = meta?.done == true

        HStack(alignment: .firstTextBaseline, spacing: LVSpacing.sm + 2) {
            if isTodo {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(palette.glowPrimary)
                    .font(.system(size: 16))
            }
            VStack(alignment: .leading, spacing: LVSpacing.xs) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .strikethrough(done, color: palette.textSecondary)
                    .lineLimit(1)
                HStack(spacing: LVSpacing.sm) {
                    if let due = meta?.dueAt {
                        Label(due.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.glowPrimary)
                    } else {
                        Text(file.path)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(Self.byteFormatter.string(fromByteCount: file.sizeBytes))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.lvTextMuted)
                }
            }
        }
        .padding(.vertical, LVSpacing.xs)
    }
}
