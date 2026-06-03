// LuminaVaultClient/LuminaVaultClient/Features/Chat/VaultNotePickerView.swift
//
// Phase 2 — `@`-reference picker. Lists the user's vault files so one can
// be attached to a chat turn as a context reference (its text is read and
// inlined into the message). Read-only over /v1/vault/files.

import LuminaVaultShared
import SwiftUI

struct VaultNotePickerView: View {
    let vaultClient: any VaultClientProtocol
    let onPick: (VaultFileDTO) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var files: [VaultFileDTO] = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    /// Display label: note title when present, else the file name.
    private func label(for file: VaultFileDTO) -> String {
        if let title = file.metadata?.title, !title.isEmpty { return title }
        return (file.path as NSString).lastPathComponent
    }

    var body: some View {
        List {
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if files.isEmpty {
                Text("No vault notes found.").foregroundStyle(.secondary)
            } else {
                ForEach(files, id: \.id) { file in
                    Button {
                        onPick(file)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label(for: file)).foregroundStyle(.primary)
                            Text(file.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        .navigationTitle("Reference a note")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search notes")
        .onSubmit(of: .search) { Task { await load() } }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = try await vaultClient.listFiles(
                spaceSlug: nil,
                q: trimmed.isEmpty ? nil : trimmed,
                before: nil,
                after: nil,
                limit: 100
            )
            files = response.files
        } catch {
            errorMessage = "Couldn't load your vault notes."
        }
    }
}
