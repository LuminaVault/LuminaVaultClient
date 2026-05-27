// LuminaVaultShareExtension/ShareRootView.swift

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
                payloadSection
                noteSection
                spaceSection
                if let message = viewModel.failureMessage() {
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
        Task {
            await viewModel.save()
            switch viewModel.saveState {
            case .saved, .queued:
                onSave()
            default:
                break
            }
        }
    }

    @ViewBuilder
    private var payloadSection: some View {
        Section {
            if viewModel.payloads.isEmpty {
                Label("Unsupported share", systemImage: "square.and.arrow.up.trianglebadge.exclamationmark")
            } else {
                ForEach(viewModel.payloads) { payload in
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(payload.title)
                                .font(.body)
                            Text(payload.subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    } icon: {
                        Image(systemName: iconName(for: payload))
                    }
                }
            }
        } footer: {
            Text("LuminaVault saves online when it can. If the network is unavailable, the app retries the capture next time it opens.")
        }
    }

    @ViewBuilder
    private var noteSection: some View {
        Section {
            TextField("Add a caption (optional)", text: $viewModel.note, axis: .vertical)
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
                Text("Pick a Space to file this capture into. Unfiled captures land at the vault root.")
            }
        }
    }

    private func iconName(for payload: SharePayload) -> String {
        switch payload {
        case .url: return "link"
        case .text: return "text.alignleft"
        case .image: return "photo"
        }
    }
}
