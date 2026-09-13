// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/RecentSavesFeed.swift
//
// What you have put in the vault, newest first, under the composer.
//
// The feed exists to make capture feel like it landed somewhere. A save that
// vanishes into a toast teaches people the app might be losing things; a row
// appearing under the composer teaches them it is not — and offline, a row
// that says "Queued" is the honest version of the same reassurance.

import SwiftUI
import LuminaVaultShared

struct RecentSavesFeed: View {
    @Environment(\.lvPalette) private var palette

    let pending: [PendingSaveUIModel]
    let files: [VaultFileDTO]
    /// Passed through to the reader. The feed lists; reading is still the
    /// vault's job, so a row is a link into it rather than an expander.
    let vaultClient: VaultClientProtocol
    let memoryClient: MemoryClientProtocol
    let isLoading: Bool
    let hasMore: Bool
    let onLoadMore: () -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: LVSpacing.sm) {
            ForEach(pending) { row in
                pendingRow(row)
            }

            ForEach(files) { file in
                NavigationLink {
                    MarkdownReaderView(
                        file: file,
                        vaultClient: vaultClient,
                        memoryClient: memoryClient
                    )
                } label: {
                    VaultFileRow(file: file)
                }
                .buttonStyle(.plain)
            }

            if isLoading && files.isEmpty && pending.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LVSpacing.lg)
            } else if files.isEmpty && pending.isEmpty {
                emptyState
            }

            if hasMore {
                // Sentinel rather than an onAppear on the last row: the last
                // row is already on screen when it appears, which fetches a
                // page nobody has scrolled toward yet.
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LVSpacing.md)
                    .onAppear(perform: onLoadMore)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: LVSpacing.xs) {
            Text("Nothing saved yet")
                .lvFont(.bodyEmphasis)
                .foregroundStyle(palette.textPrimary)
            Text("Whatever you put in the box above lands here.")
                .lvFont(.footnote)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.vertical, LVSpacing.lg)
    }

    private func pendingRow(_ row: PendingSaveUIModel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LVSpacing.sm + 2) {
            LVIconView(icon(for: row.kind), size: 14, tint: palette.textSecondary)
            VStack(alignment: .leading, spacing: LVSpacing.xs) {
                Text(row.displayText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("Queued")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, LVSpacing.xs)
        .opacity(0.7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.displayText), queued")
    }

    private func icon(for kind: PendingCaptureKind) -> LVIcon {
        switch kind {
        case .url: return .linkCircle
        case .voice: return .micFill
        case .photo: return .photoOnRectangleAngled
        case .text, .textFile: return .docText
        }
    }
}
