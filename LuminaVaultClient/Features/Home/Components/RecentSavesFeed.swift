// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/RecentSavesFeed.swift
//
// What you have put in the vault, newest first, under the composer.
//
// The feed exists to make capture feel like it landed somewhere. A save that
// vanishes into a toast teaches people the app might be losing things; a row
// appearing under the composer teaches them it is not — and offline, a row
// that says "Queued" is the honest version of the same reassurance.
//
// These are `List` rows, not a stack: the body is a flat sequence so the host
// can drop it straight into a `Section` and get separators, swipe actions and
// the system's own row metrics for free.

import SwiftUI
import LuminaVaultShared

struct RecentSavesFeed: View {
    let pending: [PendingSaveUIModel]
    let files: [VaultFileDTO]
    /// Passed through to the reader. The feed lists; reading is still the
    /// vault's job, so a row is a link into it rather than an expander.
    let vaultClient: VaultClientProtocol
    let memoryClient: MemoryClientProtocol
    let isLoading: Bool
    let hasMore: Bool
    /// The name of the Space a file was filed into, when Home knows it.
    let spaceName: (UUID?) -> String?
    let onLoadMore: () -> Void
    let onRetry: (PendingSaveUIModel) -> Void
    let onDiscard: (PendingSaveUIModel) -> Void

    var body: some View {
        Group {
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
                    VaultFileRow(file: file, spaceName: spaceName(file.spaceId))
                }
            }

            if isLoading && files.isEmpty && pending.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else if files.isEmpty && pending.isEmpty {
                emptyState
            }

            if hasMore {
                // Sentinel rather than an onAppear on the last row: the last
                // row is already on screen when it appears, which fetches a
                // page nobody has scrolled toward yet.
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .onAppear(perform: onLoadMore)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing saved yet")
                .font(.body.weight(.semibold))
            Text("Whatever you put in the box above lands here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func pendingRow(_ row: PendingSaveUIModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: row.hasFailed ? "exclamationmark.triangle.fill" : symbol(for: row.kind))
                    .font(.body)
                    .foregroundStyle(row.hasFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.displayText)
                        .font(.body)
                        .lineLimit(row.hasFailed ? 2 : 1)
                    Text(row.failure ?? "Queued")
                        .font(.footnote)
                        .foregroundStyle(row.hasFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            if row.hasFailed {
                // The capture is still in the queue and this is the only copy —
                // for a voice note the audio exists nowhere else — so discarding
                // has to be a decision rather than something that just happens.
                HStack(spacing: 16) {
                    Button("Try again") { onRetry(row) }
                    Button("Discard", role: .destructive) { onDiscard(row) }
                }
                .font(.footnote)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .opacity(row.hasFailed ? 1 : 0.7)
        .swipeActions(edge: .trailing) {
            Button("Discard", systemImage: "trash", role: .destructive) { onDiscard(row) }
        }
        .accessibilityElement(children: row.hasFailed ? .contain : .combine)
        .accessibilityLabel(row.hasFailed ? "" : "\(row.displayText), queued")
    }

    private func symbol(for kind: PendingCaptureKind) -> String {
        switch kind {
        case .url: return "link"
        case .voice: return "mic.fill"
        case .photo: return "photo"
        case .text, .textFile: return "doc.text"
        }
    }
}
