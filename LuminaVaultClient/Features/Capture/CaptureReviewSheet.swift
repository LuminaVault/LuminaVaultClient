// LuminaVaultClient/LuminaVaultClient/Features/Capture/CaptureReviewSheet.swift
//
// What to do about captures that failed.
//
// Every row here still holds its payload, so the two honest choices are to try
// again or to throw it away deliberately. Nothing on this screen deletes
// anything on the user's behalf — for a voice note the audio exists nowhere
// else, and for a note the text was cleared from the composer when it was
// enqueued.

import SwiftUI
import LuminaVaultShared

struct CaptureReviewSheet: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    let store: CaptureFailuresStore

    var body: some View {
        NavigationStack {
            Group {
                if store.rows.isEmpty {
                    LVEmptyState(
                        headline: "Nothing needs attention",
                        supporting: "Captures that fail to save will show up here so you can retry them."
                    )
                } else {
                    List {
                        Section {
                            ForEach(store.rows, id: \.id) { row in
                                rowView(row)
                            }
                        } footer: {
                            Text("These are still on this device. Retrying reuses what you captured — you do not have to redo it.")
                                .lvFont(.caption)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .lvBackground()
            .navigationTitle("Captures to review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                if !store.rows.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Retry all") { Task { await store.retryAll() } }
                    }
                }
            }
        }
        .task { await store.refresh() }
    }

    private func rowView(_ row: CaptureRowSnapshot) -> some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            Text(CaptureFailuresStore.title(for: row))
                .lvFont(.bodyEmphasis)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)

            if let reason = CaptureFailuresStore.nonEmpty(row.lastError) {
                Text(reason)
                    .lvFont(.caption)
                    .foregroundStyle(palette.accent)
                    .lineLimit(3)
            }

            Text("\(row.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(row.attempts) attempts")
                .lvFont(.caption)
                .foregroundStyle(palette.textSecondary)

            HStack(spacing: LVSpacing.lg) {
                Button("Try again") { Task { await store.retry(row) } }
                Button("Discard", role: .destructive) { Task { await store.discard(row) } }
            }
            .lvFont(.caption)
        }
        .padding(.vertical, LVSpacing.xs)
        .listRowBackground(Color.clear)
    }
}
