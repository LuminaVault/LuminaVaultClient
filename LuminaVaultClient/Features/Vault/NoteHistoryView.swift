// LuminaVaultClient/LuminaVaultClient/Features/Vault/NoteHistoryView.swift
// Backlog E4.5: a note's saved versions. Tap one to read it as it was, then
// restore it. iOS shows the version itself; the line diff is web-only in 1.0.
import SwiftUI

struct NoteHistoryView: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: NoteHistoryViewModel
    /// False for a read-only reader: versions can be read, not restored.
    let canRestore: Bool
    let onRestored: (VaultFileDTO) -> Void

    init(viewModel: NoteHistoryViewModel, canRestore: Bool, onRestored: @escaping (VaultFileDTO) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.canRestore = canRestore
        self.onRestored = onRestored
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("History")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .navigationDestination(for: VaultHistoryVersion.self) { version in
                    NoteVersionView(viewModel: viewModel, version: version, canRestore: canRestore) { file in
                        onRestored(file)
                        dismiss()
                    }
                }
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && !viewModel.hasLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.error, viewModel.versions.isEmpty {
            ContentUnavailableView {
                Label("History unavailable", systemImage: "clock.badge.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try again") { Task { await viewModel.load() } }
            }
        } else if viewModel.versions.isEmpty {
            ContentUnavailableView(
                "No saved versions yet",
                systemImage: "clock.arrow.circlepath",
                description: Text("History starts with the next save.")
            )
        } else {
            List(viewModel.versions) { version in
                NavigationLink(value: version) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(version.committedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(palette.textPrimary)
                        Text(subtitle(version))
                            .font(.system(size: 12))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .refreshable { await viewModel.load() }
        }
    }

    private func subtitle(_ version: VaultHistoryVersion) -> String {
        if version.deleted {
            return version.reasonLabel
        }
        let size = ByteCountFormatter.string(fromByteCount: version.sizeBytes, countStyle: .file)
        return "\(version.reasonLabel) · \(size)"
    }
}

extension VaultHistoryVersion: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(sha)
    }
}

private struct NoteVersionView: View {
    @Environment(\.lvPalette) private var palette

    let viewModel: NoteHistoryViewModel
    let version: VaultHistoryVersion
    let canRestore: Bool
    let onRestored: (VaultFileDTO) -> Void
    @State private var confirmRestore = false

    var body: some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if version.deleted {
                    Text("The note was deleted here. Go back and pick an earlier version to restore it.")
                        .foregroundStyle(palette.textSecondary)
                } else if viewModel.isLoadingVersion {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let text = viewModel.versionText {
                    Text(text)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if viewModel.versionIsBinary {
                    Text("No preview for this file type. You can still restore it.")
                        .foregroundStyle(palette.textSecondary)
                } else if let error = viewModel.error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .lvBackground()
        .navigationTitle(version.committedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canRestore && !version.deleted {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        confirmRestore = true
                    } label: {
                        if viewModel.isRestoring {
                            ProgressView()
                        } else {
                            Text("Restore")
                        }
                    }
                    .disabled(viewModel.isRestoring || viewModel.isLoadingVersion)
                }
            }
        }
        .confirmationDialog("Restore this version?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore") {
                Task {
                    if let file = await viewModel.restore(version) {
                        onRestored(file)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The note goes back to how it was. Today's text stays in its history.")
        }
        .alert("This note changed on another device", isPresented: $viewModel.showConflict) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Close the note and open it again, then restore. Nothing was replaced.")
        }
        .task(id: version.sha) { await viewModel.loadVersion(version) }
    }
}
