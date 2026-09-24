// LuminaVaultClient/LuminaVaultClient/Features/Settings/GmailConnectionSection.swift
//
// Muse Stage C — the Gmail row in Settings → Linked Accounts: status, the
// connected account, "Connect Gmail" (or "Reconnect Gmail" once Google has
// rejected the grant), Disconnect, and what Hermie reads. A `Section` meant to
// sit inside a `List`, beside the Google Calendar link.

import LuminaVaultShared
import SwiftUI

struct GmailConnectionSection: View {
    @State private var viewModel: GmailConnectionViewModel
    @State private var showDisconnectConfirm = false

    init(viewModel: GmailConnectionViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Section {
            content
        } header: {
            Text("Gmail")
        } footer: {
            Text(GmailConnectionViewModel.privacyLine)
        }
        .task { await viewModel.load() }
        .confirmationDialog(
            "Disconnect Gmail?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) { Task { await viewModel.disconnect() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.disconnectMessage)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity)
        case let .failed(message):
            Text(message).foregroundStyle(.red)
            Button("Retry") { Task { await viewModel.load() } }
        case let .ready(status):
            statusRows(status)
        }
        if let error = viewModel.lastError {
            Text(error).font(.footnote).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func statusRows(_ status: GmailStatusResponse) -> some View {
        LabeledContent {
            Text(viewModel.statusText)
                .foregroundStyle(viewModel.isConnected ? .green : (viewModel.needsReauth ? .orange : .secondary))
        } label: {
            Label("Status", systemImage: "envelope")
        }
        if let email = status.accountEmail, status.connected {
            LabeledContent("Account", value: email)
        }
        if status.needsReauth {
            Text("Google stopped accepting Hermie's access — reconnect to resume reading your inbox.")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
        if let label = viewModel.connectLabel {
            Button(label) { Task { await viewModel.connect() } }
                .disabled(viewModel.isWorking)
        }
        if status.connected {
            Button("Disconnect", role: .destructive) { showDisconnectConfirm = true }
                .disabled(viewModel.isWorking)
        }
    }
}
