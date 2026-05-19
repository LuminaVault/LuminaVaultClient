// LuminaVaultClient/LuminaVaultClient/Features/Capture/URLCaptureView.swift
//
// HER-257 — link capture surface. Mirrors TextCaptureView shape;
// reuses the photo flow's Space picker pattern (HER-CaptureTab).

import SwiftUI
import LuminaVaultShared

struct URLCaptureView: View {
    @State private var viewModel: URLCaptureViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: URLCaptureViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                urlSection
                noteSection
                spaceSection
            }
            .task { await viewModel.loadSpacesIfNeeded() }
            .navigationTitle("New link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await viewModel.save()
                            if viewModel.toast != nil { dismiss() }
                        }
                    } label: {
                        if viewModel.saving {
                            ProgressView()
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .disabled(!viewModel.canSave)
                }
            }
        }
    }

    @ViewBuilder
    private var urlSection: some View {
        Section {
            TextField("https://…", text: $viewModel.urlString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        } footer: {
            Text("Paste an article, X post, or YouTube link. The server resolves OG / oEmbed metadata asynchronously.")
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

    /// HER-CaptureTab — same Space picker pattern as the photo flow.
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
