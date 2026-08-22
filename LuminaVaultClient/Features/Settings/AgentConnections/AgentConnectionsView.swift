import SwiftUI
import UIKit

struct AgentConnectionsView: View {
    @State private var viewModel: AgentConnectionsViewModel
    @State private var copied = false

    init(client: any AgentConnectionsClientProtocol) {
        _viewModel = State(initialValue: AgentConnectionsViewModel(client: client))
    }

    var body: some View {
        List {
            Section {
                Text("Create a key, then paste the snippet into Claude Code, Codex, Hermes, or any MCP client. The key is shown once.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let issued = viewModel.issued {
                issuedSection(issued)
            }

            Section {
                TextField("Name (laptop, work desktop)", text: $viewModel.nameInput)
                Picker("Client", selection: $viewModel.selectedKind) {
                    ForEach(AgentClientKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .onChange(of: viewModel.selectedKind) { _, kind in
                    Task { await viewModel.selectKind(kind) }
                }
                Button("Create connection") {
                    Task { await viewModel.create() }
                }
                .disabled(viewModel.isWorking)
            } header: {
                Text("New connection")
            } footer: {
                Text("Name it after the machine the key will live on. If you lose the key, revoke it and make another.")
            }

            if let preview = viewModel.preview, viewModel.issued == nil {
                Section {
                    Text(preview.config)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                } header: {
                    Text("Setup preview — \(preview.configLabel)")
                } footer: {
                    Text("This uses a placeholder key. Create a connection to get a real one.")
                }
            }

            Section {
                if viewModel.isLoading && viewModel.connections.isEmpty {
                    ProgressView()
                } else if viewModel.connections.isEmpty {
                    Text("No agent connections yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.connections) { connection in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(connection.name)
                                .font(.body.weight(.semibold))
                            Text("\(connection.clientKind.label) · \(connection.tokenPrefix)…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(connection.lastUsedAt == nil ? "Never used" : "Last used \(connection.lastUsedAt!.formatted(.relative(presentation: .named)))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Revoke", role: .destructive) {
                                Task { await viewModel.revoke(connection) }
                            }
                        }
                    }
                }
            } header: {
                Text("Active keys")
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Agent connections")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private func issuedSection(_ issued: AgentConnectionIssuedResponse) -> some View {
        Section {
            Text("Copy this key now. LuminaVault will not show it again.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(issued.token)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
            Text(issued.setup.config)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
            if let safe = issued.setup.safe {
                Text(safe)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            }
            if let export = issued.setup.export {
                Text(export)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            }
            Button(copied ? "Copied" : "Copy setup prompt") {
                UIPasteboard.general.string = issued.setup.prompt
                copied = true
            }
            Button("Done") {
                viewModel.dismissIssued()
                copied = false
            }
        } header: {
            Text("Your key — shown once")
        }
    }
}
