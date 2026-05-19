// LuminaVaultClient/LuminaVaultClient/Features/Grok/GrokVisionView.swift
//
// HER-240c — Grok vision input + answer.

import SwiftUI

struct GrokVisionView: View {
    @State private var viewModel: GrokVisionViewModel

    init(client: any GrokClientProtocol) {
        _viewModel = State(initialValue: GrokVisionViewModel(client: client))
    }

    var body: some View {
        Form {
            Section("Image URL") {
                TextField("https://…", text: Binding(
                    get: { viewModel.imageURL },
                    set: { viewModel.imageURL = $0 },
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            }

            Section("Prompt") {
                TextField("Ask Grok about the image…", text: Binding(
                    get: { viewModel.prompt },
                    set: { viewModel.prompt = $0 },
                ), axis: .vertical)
                .lineLimit(2...4)
            }

            Section {
                Button("Analyse with Grok") {
                    Task { await viewModel.analyse() }
                }
                .buttonStyle(.borderedProminent)
            } footer: {
                Text("Grok 4.3 multimodal. Public HTTPS image URLs only in this build; base64 uploads land in a follow-up.")
            }

            switch viewModel.state {
            case .idle:
                EmptyView()
            case .analysing:
                Section { ProgressView("Analysing…").frame(maxWidth: .infinity) }
            case let .answered(response):
                Section("Answer") {
                    Text(response.answer)
                }
                Section { LabeledContent("Model", value: response.model) }
            case let .failed(message):
                Section { Text(message).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Grok Vision")
        .navigationBarTitleDisplayMode(.inline)
    }
}
