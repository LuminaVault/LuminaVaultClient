// LuminaVaultClient/LuminaVaultClient/Features/Capture/TextCaptureView.swift
//
// HER-256 — text capture surface. Mirrors `CapturePhotosView` shape
// (NavigationStack + List sections + Cancel/Save toolbar) so the FAB
// sheet feels uniform across modes.

import SwiftUI

struct TextCaptureView: View {
    @State private var viewModel: TextCaptureViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: TextCaptureViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                bodySection
                locationSection
            }
            .navigationTitle("New memory")
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
    private var bodySection: some View {
        Section {
            TextField(
                "What's on your mind?",
                text: $viewModel.content,
                axis: .vertical,
            )
            .lineLimit(5 ... 12)
            .textInputAutocapitalization(.sentences)
        } footer: {
            Text("Plain text. Saves directly to your memory vault — no synthesis, no editing flow.")
        }
    }

    private var locationSection: some View {
        Section {
            Toggle(isOn: $viewModel.locationEnabled) {
                Label("Tag with current location", systemImage: "location")
            }
        } footer: {
            Text("Off by default. Turning it on for this memory sends one location fix and the place name.")
        }
    }
}
