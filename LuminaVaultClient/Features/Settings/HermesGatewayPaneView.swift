// LuminaVaultClient/LuminaVaultClient/Features/Settings/HermesGatewayPaneView.swift
//
// HER-218 — Settings → Advanced → Hermes Gateway pane.

import SwiftUI

struct HermesGatewayPaneView: View {
    @State private var viewModel: HermesGatewayViewModel
    @State private var showDisconnectConfirm = false

    init(client: any SettingsClientProtocol) {
        _viewModel = State(initialValue: HermesGatewayViewModel(client: client))
    }

    var body: some View {
        List {
            switch viewModel.state {
            case .loading:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case .empty:
                emptyStateSection
            case let .configured(baseUrl, hasAuthHeader, status):
                configuredSection(baseUrl: baseUrl, hasAuthHeader: hasAuthHeader, status: status)
            case let .editing(prefilledBaseUrl, prefilledHasAuthHeader):
                editingSection(prefilledBaseUrl: prefilledBaseUrl, prefilledHasAuthHeader: prefilledHasAuthHeader)
            }

            if let error = viewModel.lastError {
                Section { Text(error).foregroundStyle(.red) }
            }
            if let verifyError = viewModel.verifyError {
                Section {
                    Text(verifyError.displayMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Hermes Gateway")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    // MARK: - Sections

    private var emptyStateSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Using LuminaVault managed Hermes.")
                    .font(.body)
                Button("Use my own gateway →") { viewModel.useMyOwnGateway() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
        } footer: {
            Text("Point LuminaVault at a self-hosted hermes-agent instance. You'll need the base URL and (optionally) an authorization header.")
        }
    }

    @ViewBuilder
    private func configuredSection(
        baseUrl: String,
        hasAuthHeader: Bool,
        status: HermesGatewayViewModel.VerifyStatus,
    ) -> some View {
        Section("Configured Gateway") {
            LabeledContent("Base URL", value: baseUrl)
            LabeledContent("Auth header", value: hasAuthHeader ? "Set" : "None")
            switch status {
            case .unverified:
                LabeledContent("Status", value: "Not verified")
                    .foregroundStyle(.secondary)
            case .verified(let at):
                LabeledContent("Verified", value: at.formatted(.relative(presentation: .named)))
                    .foregroundStyle(.green)
            }
        }
        Section {
            Button("Test again") { Task { await viewModel.testAgain() } }
                .disabled(viewModel.isWorking)
            Button("Update token") { viewModel.editExistingConfig() }
                .disabled(viewModel.isWorking)
            Button("Disconnect", role: .destructive) { showDisconnectConfirm = true }
                .disabled(viewModel.isWorking)
        }
        .confirmationDialog(
            "Stop using your own gateway?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible,
        ) {
            Button("Disconnect", role: .destructive) {
                Task { await viewModel.disconnect() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("LuminaVault will go back to the managed Hermes gateway. Your existing memories and vault are untouched.")
        }
    }

    @ViewBuilder
    private func editingSection(prefilledBaseUrl: String?, prefilledHasAuthHeader: Bool) -> some View {
        Section("Gateway URL") {
            TextField("https://hermes.example.com", text: $viewModel.baseUrlInput)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } footer: {
            Text("Must use https://. Self-signed certificates are not supported.")
        }

        Section("Authorization") {
            SecureField(prefilledHasAuthHeader ? "Replace token (optional)" : "Bearer abc123 (optional)", text: $viewModel.authHeaderInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } footer: {
            Text("Paste the full header value. Leave empty if your gateway is unauthenticated. Not returned in plaintext after save.")
        }

        Section {
            Button("Save & verify") { Task { await viewModel.submit() } }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isWorking || viewModel.baseUrlInput.isEmpty)
            Button("Cancel") { Task { await viewModel.cancelEditing() } }
                .disabled(viewModel.isWorking)
        }
    }
}
