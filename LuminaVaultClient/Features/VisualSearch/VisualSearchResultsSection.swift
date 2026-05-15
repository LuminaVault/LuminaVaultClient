// LuminaVaultClient/LuminaVaultClient/Features/VisualSearch/VisualSearchResultsSection.swift
//
// HER-157 — pure presentational sub-view rendering `QueryResponse`.
// Lives in its own file so the share extension (HER-110) and a future
// long-press surface (HER-105) can drop it in without re-implementing
// the layout.

import SwiftUI

struct VisualSearchResultsSection: View {
    let response: QueryResponse
    let extractedText: String

    var body: some View {
        Group {
            Section("Hermes says") {
                Text(response.summary)
                    .font(.body)
            }

            Section("Recognised text") {
                Text(extractedText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if response.hits.isEmpty {
                Section { Text("No matching memories.").foregroundStyle(.secondary) }
            } else {
                Section("Memory hits") {
                    ForEach(response.hits) { hit in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(hit.content)
                                .font(.body)
                                .lineLimit(4)
                            HStack {
                                Text(String(format: "Distance %.2f", hit.distance))
                                if let createdAt = hit.createdAt {
                                    Text("·").foregroundStyle(.secondary)
                                    Text(createdAt.formatted(date: .abbreviated, time: .omitted))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}
