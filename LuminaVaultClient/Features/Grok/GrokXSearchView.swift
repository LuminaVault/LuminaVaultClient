// LuminaVaultClient/LuminaVaultClient/Features/Grok/GrokXSearchView.swift
//
// HER-240c — `x_search` query + results screen.

import SwiftUI

struct GrokXSearchView: View {
    @State private var viewModel: GrokXSearchViewModel

    init(client: any GrokClientProtocol) {
        _viewModel = State(initialValue: GrokXSearchViewModel(client: client))
    }

    var body: some View {
        Form {
            Section {
                TextField("Search X posts…", text: Binding(
                    get: { viewModel.query },
                    set: { viewModel.query = $0 },
                ), axis: .vertical)
                .lineLimit(2...4)
                Button("Search") {
                    Task { await viewModel.search() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || viewModel.state == .searching)
            } footer: {
                Text("Powered by Grok's x_search tool. Returns a synthesised answer plus citations to original posts.")
            }

            switch viewModel.state {
            case .idle:
                EmptyView()
            case .searching:
                Section { ProgressView("Asking Grok…").frame(maxWidth: .infinity) }
            case let .results(response):
                Section("Answer") {
                    Text(response.answer)
                }
                if !response.citations.isEmpty {
                    Section("Citations") {
                        ForEach(response.citations) { citation in
                            if let url = URL(string: citation.url) {
                                Link(destination: url) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(citation.title ?? citation.url)
                                            .font(.body)
                                            .lineLimit(2)
                                        Text(citation.url)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
            case let .failed(message, _):
                Section { Text(message).foregroundStyle(.red) }
            }
        }
        .navigationTitle("X Search")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension GrokXSearchViewModel.State {
    static func == (lhs: GrokXSearchViewModel.State, rhs: GrokXSearchViewModel.State) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.searching, .searching): return true
        default: return false
        }
    }
}
