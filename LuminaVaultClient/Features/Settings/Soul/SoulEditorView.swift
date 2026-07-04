// LuminaVaultClient/LuminaVaultClient/Features/Settings/Soul/SoulEditorView.swift
//
// Phase 1 — Settings → Your Agent → Personality. View/edit/reset the
// per-user SOUL.md that Hermes loads every turn. Presets seed the editor;
// the user reviews and saves explicitly.

import LuminaVaultShared
import SwiftUI

struct SoulEditorView: View {
    @State private var viewModel: SoulEditorViewModel
    @State private var showResetConfirm = false

    init(client: any SoulClientProtocol) {
        _viewModel = State(initialValue: SoulEditorViewModel(client: client))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                editor
            case let .failed(message):
                VStack(spacing: 12) {
                    Text(message).foregroundStyle(.red)
                    Button("Retry") { Task { await viewModel.load() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Personality")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { Task { await viewModel.save() } }
                    .disabled(!viewModel.canSave)
            }
        }
    }

    private var editor: some View {
        Form {
            Section {
                Menu {
                    ForEach(SoulPreset.allCases) { preset in
                        Button(preset.rawValue) { viewModel.applyPreset(preset) }
                    }
                } label: {
                    Label("Apply a preset", systemImage: "wand.and.stars")
                }
            } footer: {
                Text("Presets fill the editor with a starting personality. Review and save to apply.")
            }

            if let core = viewModel.lockedCore {
                Section {
                    SoulLockedCoreCard(core: core)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("The core covenant is managed by LuminaVault and re-applied on every save.")
                }
            }

            Section {
                TextEditor(text: $viewModel.markdown)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 280)
                    .disabled(viewModel.isSaving)
            } header: {
                Text("SOUL.md")
            } footer: {
                HStack {
                    Text("\(viewModel.byteCount) / \(SoulEditorViewModel.maxBytes) bytes")
                        .foregroundStyle(viewModel.isOverLimit ? .red : .secondary)
                    if viewModel.isOverLimit {
                        Text("— too large").foregroundStyle(.red)
                    }
                    Spacer()
                    if let updatedAt = viewModel.updatedAt {
                        Text("Updated \(updatedAt.formatted(.relative(presentation: .named)))")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }

            if let error = viewModel.actionError {
                Section { Text(error).foregroundStyle(.red) }
            }

            Section {
                Button("Revert changes") { viewModel.revert() }
                    .disabled(!viewModel.isDirty || viewModel.isSaving)
                Button("Reset to default", role: .destructive) { showResetConfirm = true }
                    .disabled(viewModel.isSaving)
            }
        }
        .confirmationDialog(
            "Reset personality to default?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                Task { await viewModel.resetToDefault() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Replaces SOUL.md with the bootstrap template. This can't be undone.")
        }
    }
}
