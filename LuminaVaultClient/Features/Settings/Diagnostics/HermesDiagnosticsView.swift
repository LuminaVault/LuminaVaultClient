// LuminaVaultClient/LuminaVaultClient/Features/Settings/Diagnostics/HermesDiagnosticsView.swift
//
// Phase 1 — Settings → System & Advanced → Diagnostics. Read-only snapshot
// of how the user's agent is wired: brain mode, active model + fallback
// chain, provider credential health, Nous Portal link, and (for BYO-Hermes)
// an on-demand reachability probe.

import LuminaVaultShared
import SwiftUI

struct HermesDiagnosticsView: View {
    @State private var viewModel: HermesDiagnosticsViewModel

    init(
        llmClient: any LLMPreferencesClientProtocol,
        providersClient: any ProvidersClientProtocol,
        integrationsClient: any IntegrationsClientProtocol,
        settingsClient: any SettingsClientProtocol
    ) {
        _viewModel = State(initialValue: HermesDiagnosticsViewModel(
            llmClient: llmClient,
            providersClient: providersClient,
            integrationsClient: integrationsClient,
            settingsClient: settingsClient
        ))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                content
            case let .failed(message):
                VStack(spacing: 12) {
                    Text(message).foregroundStyle(.red)
                    Button("Retry") { Task { await viewModel.load() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    private var content: some View {
        List {
            brainSection
            providersSection
            nousSection
            if viewModel.hermesConfig != nil { hermesServerSection }
            if !viewModel.sectionErrors.isEmpty { errorsSection }
        }
        .refreshable { await viewModel.load() }
    }

    @ViewBuilder private var brainSection: some View {
        Section("Brain") {
            if let prefs = viewModel.preferences {
                row("Mode", prefs.mode == .managed ? "Managed" : "Your keys (BYOK)")
                row("Active model", prefs.primaryModel)
                row("Provider", prefs.primaryProvider.diagnosticsLabel)
                if !prefs.fallbackChain.isEmpty {
                    row("Fallbacks", "\(prefs.fallbackChain.count)")
                    ForEach(prefs.fallbackChain, id: \.self) { route in
                        Text("↳ \(route.provider.diagnosticsLabel) · \(route.model)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Unavailable").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var providersSection: some View {
        Section("Providers") {
            let provs = viewModel.credentialedProviders
            if provs.isEmpty {
                Text("No provider keys configured").foregroundStyle(.secondary)
            } else {
                ForEach(provs, id: \.provider) { p in
                    HStack {
                        Text(p.provider.diagnosticsLabel)
                        Spacer()
                        providerStatus(p)
                    }
                }
            }
        }
    }

    @ViewBuilder private func providerStatus(_ p: ProviderCredentialDTO) -> some View {
        if let failure = p.lastFailureAt, (p.verifiedAt == nil || failure > p.verifiedAt!) {
            Label(p.lastFailureCode ?? "Error", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        } else if p.verifiedAt != nil {
            Label("Verified", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.caption)
        } else {
            Label("Untested", systemImage: "circle.dashed")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    @ViewBuilder private var nousSection: some View {
        Section("Nous Portal") {
            if let nous = viewModel.nous {
                row("Connected", nous.connected ? "Yes" : "No")
                if let plan = nous.plan { row("Plan", plan) }
            } else {
                Text("Unavailable").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var hermesServerSection: some View {
        Section("Hermes Server (BYO)") {
            if let config = viewModel.hermesConfig {
                row("Endpoint", config.baseUrl)
                row("Auth header", config.hasAuthHeader ? "Set" : "None")
            }
            HStack {
                Button("Test connection") { Task { await viewModel.probeHermes() } }
                    .disabled(viewModel.hermesProbe == .running)
                Spacer()
                switch viewModel.hermesProbe {
                case .idle: EmptyView()
                case .running: ProgressView()
                case let .ok(date):
                    Label(date.formatted(.relative(presentation: .named)), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.caption)
                case let .failed(message):
                    Label(message, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red).font(.caption)
                }
            }
        }
    }

    @ViewBuilder private var errorsSection: some View {
        Section("Couldn't load") {
            ForEach(viewModel.sectionErrors, id: \.self) { err in
                Text(err).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}
