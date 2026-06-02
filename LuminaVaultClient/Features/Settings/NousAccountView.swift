// LuminaVaultClient/LuminaVaultClient/Features/Settings/NousAccountView.swift
//
// Nous Subscription Integration — Settings → Connections → Connect Nous
// Account. Surfaces the Nous Portal connection state and drives the OAuth
// device-code flow: Connect opens the verification URL in a browser and
// displays the user-code; once the user approves, "I've approved" completes
// the handshake. Disconnect reverts to LuminaVault's managed Hermes.

import SwiftUI

struct NousAccountView: View {
    @State private var viewModel: NousAccountViewModel
    @State private var showConnectSheet = false
    @State private var showDisconnectConfirm = false

    /// Static management page — Nous exposes no in-app billing, so we deep
    /// link out for subscription management/top-up.
    private static let manageURL = URL(string: "https://portal.nousresearch.com/manage-subscription")!

    init(client: any IntegrationsClientProtocol) {
        _viewModel = State(initialValue: NousAccountViewModel(client: client))
    }

    var body: some View {
        List {
            switch viewModel.state {
            case .loading:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case let .ready(status):
                nousSection(status: status)
            case let .failed(message):
                Section {
                    Text(message).foregroundStyle(.red)
                    Button("Retry") { Task { await viewModel.load() } }
                }
            }

            if let err = viewModel.actionError {
                Section { Text(err).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Connect Nous Account")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .sheet(isPresented: $showConnectSheet, onDismiss: { viewModel.cancelConnect() }) {
            NousConnectSheet(viewModel: viewModel, isPresented: $showConnectSheet)
        }
        .confirmationDialog(
            "Disconnect Nous account?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible,
        ) {
            Button("Disconnect", role: .destructive) {
                Task { await viewModel.disconnect() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the Nous credential from your Hermes container and reverts to LuminaVault's managed Hermes. You can reconnect any time.")
        }
    }

    @ViewBuilder
    private func nousSection(status: NousStatusResponse) -> some View {
        Section("Nous Portal") {
            LabeledContent("Status", value: status.connected ? "Connected" : "Not connected")
                .foregroundStyle(status.connected ? .green : .secondary)
            if let plan = status.plan {
                LabeledContent("Plan", value: plan)
            }
            if let connectedAt = status.nousConnectedAt {
                LabeledContent("Since") {
                    Text(connectedAt, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section {
            if status.connected {
                Button("Disconnect", role: .destructive) {
                    showDisconnectConfirm = true
                }
                .disabled(viewModel.isWorking)
            } else {
                Button("Connect Nous Account") {
                    showConnectSheet = true
                    Task { await viewModel.startConnect() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isWorking)
            }
            Link("Manage on Nous ↗", destination: Self.manageURL)
        } footer: {
            Text(status.connected
                ? "All your chat, memory, and tool calls run on your own Nous subscription."
                : "Connect your existing Nous Portal subscription so requests use your own credits instead of LuminaVault's managed Hermes.")
        }
    }
}

/// Device-code connect sheet: opens the verification URL, shows the
/// user-code, and completes once the user confirms they've approved.
private struct NousConnectSheet: View {
    @Bindable var viewModel: NousAccountViewModel
    @Binding var isPresented: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                switch viewModel.connectPhase {
                case .idle, .starting:
                    Section {
                        HStack {
                            ProgressView()
                            Text("Preparing Nous sign-in…").foregroundStyle(.secondary)
                        }
                    }
                case let .awaitingApproval(start):
                    approvalSection(start: start)
                case .completing:
                    Section {
                        HStack {
                            ProgressView()
                            Text("Finishing sign-in…").foregroundStyle(.secondary)
                        }
                    }
                }

                if let err = viewModel.actionError {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Connect Nous")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelConnect()
                        isPresented = false
                    }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isWorking)
    }

    @ViewBuilder
    private func approvalSection(start: NousStartResponse) -> some View {
        Section {
            if let code = start.userCode {
                LabeledContent("Your code") {
                    Text(code)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                }
            }
            Button("Open Nous sign-in") {
                if let url = URL(string: start.verifyURL) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
        } header: {
            Text("Step 1 — Approve in browser")
        } footer: {
            Text("Open the Nous sign-in page, confirm the code above, and approve access. Then return here.")
        }

        Section {
            Button("I've approved — finish") {
                Task { await viewModel.completeConnect() }
            }
            .disabled(viewModel.isWorking)
        } footer: {
            Text("Step 2 — we'll finish connecting your subscription. This can take a few seconds.")
        }
    }
}
