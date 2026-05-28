// LuminaVaultClient/LuminaVaultClient/Features/Reflect/SavedReflectionsListView.swift
//
// HER-194 — recent-reflections feed. Each row navigates to the existing
// `MarkdownReaderView` which already handles wikilink resolution.

import LuminaVaultShared
import SwiftUI

struct SavedReflectionsListView: View {
    @Environment(\.lvPalette) private var palette

    let files: [VaultFileDTO]
    let vaultClient: VaultClientProtocol
    let memoryClient: MemoryClientProtocol

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent (last 10)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20)

            if files.isEmpty {
                Text("No reflections yet. Tap a card above to start.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 20)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(files) { file in
                        NavigationLink {
                            MarkdownReaderView(
                                file: file,
                                vaultClient: vaultClient,
                                memoryClient: memoryClient,
                            )
                        } label: {
                            row(for: file)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func row(for file: VaultFileDTO) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle(for: file))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(relativeDate(file.createdAt ?? Date()))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func displayTitle(for file: VaultFileDTO) -> String {
        let base = (file.path as NSString).lastPathComponent
        return (base as NSString).deletingPathExtension
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
