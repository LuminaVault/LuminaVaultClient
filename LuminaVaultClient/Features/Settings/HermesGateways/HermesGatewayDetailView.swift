// LuminaVaultClient/LuminaVaultClient/Features/Settings/HermesGateways/HermesGatewayDetailView.swift
//
// HER-241 — per-gateway detail screen. Renders the field set declared
// by the server (text / secret / url) and surfaces the CLI command
// users must run on their Hermes host until upstream ships an admin
// HTTP API.

import LuminaVaultShared
import SwiftUI

struct HermesGatewayDetailView: View {
    let gatewayID: HermesGatewayID
    @State private var viewModel: HermesGatewayDetailViewModel
    @State private var showDisconnectConfirm = false

    init(gatewayID: HermesGatewayID, client: any HermesGatewaysClientProtocol) {
        self.gatewayID = gatewayID
        _viewModel = State(initialValue: HermesGatewayDetailViewModel(gatewayID: gatewayID, client: client))
    }

    var body: some View {
        Form {
            switch viewModel.loadingState {
            case .loading:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case let .loadFailed(message):
                Section { Text(message).foregroundStyle(.red) }
            case .ready:
                if let entry = viewModel.entry {
                    fieldSection(entry: entry)
                    actionSection(entry: entry)
                    if entry.hasConfig {
                        manualCliSection
                    }
                    outcomeSection
                }
            }
        }
        .navigationTitle(viewModel.entry?.displayName ?? "Gateway")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    // MARK: - Sections

    @ViewBuilder
    private func fieldSection(entry: HermesGatewayCatalogEntry) -> some View {
        Section {
            Text(entry.description).font(.callout).foregroundStyle(.secondary)
        }
        Section("Configuration") {
            ForEach(entry.requiredFields, id: \.key) { field in
                fieldEditor(field)
            }
        }
    }

    @ViewBuilder
    private func fieldEditor(_ field: HermesGatewayField) -> some View {
        let binding = Binding(
            get: { viewModel.values[field.key] ?? "" },
            set: { viewModel.values[field.key] = $0 },
        )
        VStack(alignment: .leading, spacing: 4) {
            Text(field.label).font(.caption).foregroundStyle(.secondary)
            switch field.kind {
            case .secret:
                SecureField(field.placeholder ?? "", text: binding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            case .url:
                TextField(field.placeholder ?? "https://…", text: binding)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            case .text:
                TextField(field.placeholder ?? "", text: binding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func actionSection(entry: HermesGatewayCatalogEntry) -> some View {
        Section {
            Button("Save & test connection") {
                Task { await viewModel.saveAndTest() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.save == .saving)

            if entry.hasConfig {
                Button("Disconnect", role: .destructive) { showDisconnectConfirm = true }
                    .disabled(viewModel.isDeleting)
            }
        }
        .confirmationDialog(
            "Remove \(entry.displayName) config?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible,
        ) {
            Button("Remove", role: .destructive) {
                Task { await viewModel.disconnect() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("LuminaVault deletes the stored config. The gateway running on your Hermes host stays up until you stop it with `hermes gateway stop`.")
        }
    }

    @ViewBuilder
    private var manualCliSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Run on your Hermes host")
                    .font(.subheadline.weight(.medium))
                HStack {
                    Text(viewModel.manualCliCommand)
                        .font(.system(.callout, design: .monospaced))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Spacer()
                    Button {
                        UIPasteboard.general.string = viewModel.manualCliCommand
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }
        } footer: {
            Text("Hermes does not yet expose an admin HTTP API for gateway setup. Run this on your Hermes host once, then restart Hermes to pick up the change. (`hermes gateway restart`)")
        }
    }

    @ViewBuilder
    private var outcomeSection: some View {
        switch viewModel.save {
        case .idle, .saving:
            EmptyView()
        case let .saved(verifyOk, errorCode):
            Section {
                if verifyOk {
                    Label("Hermes reachable. Config saved.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Saved. Hermes not reachable: \(errorCode ?? "unknown")", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        case let .error(message):
            Section { Text(message).foregroundStyle(.red) }
        }
    }
}
