// LuminaVaultClient/LuminaVaultClient/Features/Capture/CapturePhotosView.swift
//
// HER-34 — sheet surface for the "+" FAB. Photos multi-select, per-
// photo caption, optional location toggle, single Save CTA. Save
// dismisses the sheet immediately and shows a toast; the actual
// upload happens on `CaptureDrainer`.

import PhotosUI
import SwiftUI

struct CapturePhotosView: View {
    @State private var viewModel: CapturePhotosViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: CapturePhotosViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                pickerSection
                if !viewModel.loadedItems.isEmpty {
                    capturesSection
                    spaceSection
                    locationSection
                }
            }
            .task { await viewModel.loadSpacesIfNeeded() }
            .navigationTitle("New capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await viewModel.save()
                            dismiss()
                        }
                    } label: {
                        if viewModel.saving {
                            ProgressView()
                        } else {
                            Text("Save \(viewModel.loadedItems.isEmpty ? "" : "(\(viewModel.loadedItems.count))")")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(viewModel.loadedItems.isEmpty || viewModel.saving)
                }
            }
        }
    }

    private var pickerSection: some View {
        Section {
            PhotosPicker(
                selection: $viewModel.pickerItems,
                maxSelectionCount: 10,
                matching: .images,
                photoLibrary: .shared(),
            ) {
                Label("Pick photos", systemImage: "photo.on.rectangle.angled")
            }
        } footer: {
            Text("HEIC and JPEG both upload losslessly. Captures sync when you're online.")
        }
    }

    @ViewBuilder
    private var capturesSection: some View {
        Section("Captures") {
            ForEach($viewModel.loadedItems) { $item in
                HStack(alignment: .top, spacing: 12) {
                    if let uiImage = UIImage(data: item.data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    TextField("Add a caption (optional)", text: $item.caption, axis: .vertical)
                        .lineLimit(1 ... 3)
                }
            }
        }
    }

    private var locationSection: some View {
        Section {
            Toggle(isOn: $viewModel.locationEnabled) {
                Label("Tag with current location", systemImage: "location")
            }
        } footer: {
            Text("Off by default. Turning it on for this capture sends one location fix and the place name with the memory.")
        }
    }

    /// HER-CaptureTab — Space picker section. Only renders when the user
    /// has at least one Space; absence leaves the capture unfiled.
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
}
