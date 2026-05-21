// LuminaVaultShareExtension/ShareRootView.swift
//
// HER-258 — SwiftUI surface inside the share sheet. Mirrors
// `URLCaptureView` (URL + note + Space picker) so users see the same
// shape whether they capture from inside the app or from Safari/X/YT.

import SwiftUI

struct ShareRootView: View {
    @State private var viewModel: ShareViewModel
    let onCancel: () -> Void
    let onSave: () -> Void

    init(
        viewModel: ShareViewModel,
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                urlSection
                noteSection
                spaceSection
                if case .failed(let message) = viewModel.saveState {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Save to LuminaVault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: saveAndClose) {
                        switch viewModel.saveState {
                        case .saving: ProgressView()
                        default: Text("Save").fontWeight(.semibold)
                        }
                    }
                    .disabled(!viewModel.canSave)
                }
            }
        }
    }

    private func saveAndClose() {
        viewModel.save()
        if case .saved = viewModel.saveState {
            onSave()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var urlSection: some View {
        Section {
            TextField("https://…", text: $viewModel.urlString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        } footer: {
            Text("LuminaVault enriches links (Open Graph, oEmbed, X post metadata) in the background once you reopen the app.")
        }
    }

    @ViewBuilder
    private var noteSection: some View {
        Section {
            TextField("Add a note (optional)", text: $viewModel.note, axis: .vertical)
                .lineLimit(1 ... 4)
                .textInputAutocapitalization(.sentences)
        }
    }

    @ViewBuilder
    private var spaceSection: some View {
        if let spaces = viewModel.availableSpaces, !spaces.isEmpty {
            Section {
                Picker(selection: $viewModel.selectedSpaceID) {
                    Text("Unfiled").tag(UUID?.none)
                    ForEach(spaces, id: \.id) { space in
                        Text(space.name).tag(UUID?.some(space.id))
                    }
                } label: {
                    Label("Space", systemImage: "folder")
                }
                .pickerStyle(.menu)
            } footer: {
                Text("Pick a Space to file this link into. Unfiled links land at the vault root.")
            }
        }
    }
}
