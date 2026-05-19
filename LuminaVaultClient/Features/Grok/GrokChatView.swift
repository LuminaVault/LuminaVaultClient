// LuminaVaultClient/LuminaVaultClient/Features/Grok/GrokChatView.swift
//
// HER-240c — minimal single-turn Grok chat.

import SwiftUI

struct GrokChatView: View {
    @State private var viewModel: GrokChatViewModel

    init(client: any GrokClientProtocol) {
        _viewModel = State(initialValue: GrokChatViewModel(client: client))
    }

    var body: some View {
        Form {
            Section {
                TextField("Ask Grok anything…", text: Binding(
                    get: { viewModel.prompt },
                    set: { viewModel.prompt = $0 },
                ), axis: .vertical)
                .lineLimit(2...8)
                Button("Send") {
                    Task { await viewModel.ask() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                Text("Direct chat with Grok 4.x via your connected xAI subscription.")
            }

            switch viewModel.state {
            case .idle:
                EmptyView()
            case .thinking:
                Section { ProgressView("Thinking…").frame(maxWidth: .infinity) }
            case let .answered(response):
                Section("Answer") {
                    Text(response.answer)
                }
                Section("Details") {
                    LabeledContent("Model", value: response.model)
                    if let usage = response.usage {
                        LabeledContent("Tokens in", value: "\(usage.promptTokens)")
                        LabeledContent("Tokens out", value: "\(usage.completionTokens)")
                    }
                }
            case let .failed(message):
                Section { Text(message).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Grok Chat")
        .navigationBarTitleDisplayMode(.inline)
    }
}
