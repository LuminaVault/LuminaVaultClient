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
                    applyProgressSection
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
            Button("Save & apply") {
                Task { await viewModel.saveAndApply() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.save == .saving || viewModel.applyPhase == .applying)

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
    private var applyProgressSection: some View {
        if viewModel.applyPhase != .idle {
            Section("Applying to your assistant") {
                if viewModel.applySteps.isEmpty, viewModel.applyPhase == .applying {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Starting…").foregroundStyle(.secondary)
                    }
                }
                ForEach(viewModel.applySteps) { step in
                    applyStepRow(step)
                }
            }
        }
    }

    @ViewBuilder
    private func applyStepRow(_ step: HermesGatewayApplyStep) -> some View {
        let style = Self.stepIcon(step.state)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: style.symbol)
                .foregroundStyle(style.color)
                .symbolEffect(.pulse, isActive: step.state == .running)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.stepLabel(step.id))
                if let detail = step.detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if step.state == .running { ProgressView() }
        }
        .padding(.vertical, 2)
    }

    private static func stepLabel(_ id: HermesGatewayApplyStepID) -> String {
        switch id {
        case .writeEnv: "Writing your settings"
        case .restartContainer: "Restarting your assistant"
        case .healthCheck: "Checking it responds"
        }
    }

    private static func stepIcon(_ state: HermesGatewayApplyStepState) -> (symbol: String, color: Color) {
        switch state {
        case .pending: ("circle", .secondary)
        case .running: ("arrow.triangle.2.circlepath", .blue)
        case .succeeded: ("checkmark.circle.fill", .green)
        case .failed: ("xmark.circle.fill", .red)
        case .skipped: ("minus.circle", .secondary)
        }
    }

    @ViewBuilder
    private var outcomeSection: some View {
        switch viewModel.applyPhase {
        case .succeeded:
            Section {
                Label("Connected. Your assistant is live on this platform.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        case let .failed(message):
            Section { Text(message).foregroundStyle(.red) }
        case .idle, .applying:
            // Surface a pre-apply save error (e.g. validation / upsert failure).
            if case let .error(message) = viewModel.save {
                Section { Text(message).foregroundStyle(.red) }
            }
        }
    }
}
