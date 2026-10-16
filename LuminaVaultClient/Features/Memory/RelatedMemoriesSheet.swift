// LuminaVaultClient/LuminaVaultClient/Features/Memory/RelatedMemoriesSheet.swift
//
// "Connects to N memories" — what a save turned out to be near, opened from
// the banner Home shows a moment after the drainer lands it. Each row opens
// the memory itself, pushed inside this sheet.

import LuminaVaultShared
import SwiftUI

struct RelatedMemoriesSheet: View {
    let items: [RelatedMemoryDTO]
    let client: any MemoryClientProtocol
    var spacesClient: (any SpacesClientProtocol)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { item in
                        NavigationLink {
                            MemoryDetailView(memoryID: item.id, client: client, spacesClient: spacesClient)
                        } label: {
                            RelatedMemoryRow(item: item)
                        }
                    }
                } footer: {
                    Text("Memories closest in meaning to what you just saved.")
                }
            }
            .navigationTitle("Connects to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// One related memory: the snippet, its kind and when it was saved.
struct RelatedMemoryRow: View {
    let item: RelatedMemoryDTO

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.xs) {
            Text(item.snippet)
                .lvFont(.body)
                .lineLimit(3)
            HStack(spacing: LVSpacing.sm) {
                if let kind = item.kind {
                    MemoryKindChip(kind: kind)
                }
                Text(item.createdAt, format: .dateTime.month(.abbreviated).day().year())
                    .lvFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, LVSpacing.hairline)
        .accessibilityElement(children: .combine)
    }
}

/// The small capsule the memory browser uses for a memory's kind.
struct MemoryKindChip: View {
    let kind: MemoryKindDTO

    var body: some View {
        Text(kind.label)
            .lvFont(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}
