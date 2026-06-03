// LuminaVaultClient/LuminaVaultClient/Features/Settings/LinkedAccountsView.swift
//
// HER-240b — Settings → Connections → Linked Accounts.
//
// Today: surfaces the xAI Grok OAuth state, lets the user connect (sheet)
// or disconnect. The X (Twitter) sign-in identity row will be wired here
// once `MeResponse` carries the linked X handle (HER-240b iOS PR follow-up
// / HER-240c).

import SwiftUI

struct LinkedAccountsView: View {
    @State private var viewModel: LinkedAccountsViewModel
    @State private var showConnectSheet = false
    @State private var showDisconnectConfirm = false
    private let client: any IntegrationsClientProtocol

    init(client: any IntegrationsClientProtocol) {
        self.client = client
        _viewModel = State(initialValue: LinkedAccountsViewModel(client: client))
    }

    var body: some View {
        List {
            switch viewModel.state {
            case .loading:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case let .ready(status):
                xaiSection(status: status)
            case let .failed(message):
                Section {
                    Text(message).foregroundStyle(.red)
                    Button("Retry") { Task { await viewModel.load() } }
                }
            }

            if let err = viewModel.disconnectError {
                Section { Text(err).foregroundStyle(.red) }
            }

            // HER-340 — Google Calendar (server-owned OAuth data source).
            Section {
                NavigationLink {
                    CalendarSettingsView()
                } label: {
                    Label("Google Calendar", systemImage: "calendar")
                }
            } footer: {
                Text("Connect your calendar so Hermes knows your schedule.")
            }
        }
        .navigationTitle("Linked Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .sheet(isPresented: $showConnectSheet) {
            GrokConnectFlowView(client: client) { status in
                viewModel.applyConnectResult(status)
            }
        }
        .confirmationDialog(
            "Disconnect xAI Grok?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible,
        ) {
            Button("Disconnect", role: .destructive) {
                Task { await viewModel.disconnect() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the xAI session from this device's Hermes container and reverts your tier to trial. You can reconnect any time.")
        }
    }

    @ViewBuilder
    private func xaiSection(status: XaiStatusResponse) -> some View {
        Section("xAI Grok") {
            LabeledContent("Status", value: status.connected ? "Connected" : "Not connected")
                .foregroundStyle(status.connected ? .green : .secondary)
            LabeledContent("Tier", value: status.tier.capitalized)
            if let connectedAt = status.xaiConnectedAt {
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
                Button("Connect with xAI") {
                    showConnectSheet = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isWorking)
            }
        } footer: {
            Text("Connecting unlocks Grok 4.x chat, X search, image understanding, and TTS for your account. You'll sign in with your X (SuperGrok) credentials.")
        }

        if status.connected {
            grokFeaturesSection
        }
    }

    private var grokFeaturesSection: some View {
        Section("Grok Features") {
            NavigationLink {
                GrokChatView(client: grokClient)
            } label: {
                Label("Chat with Grok", systemImage: "bubble.left.and.bubble.right")
            }
            NavigationLink {
                GrokXSearchView(client: grokClient)
            } label: {
                Label("X Search", systemImage: "magnifyingglass")
            }
            NavigationLink {
                GrokVisionView(client: grokClient)
            } label: {
                Label("Vision", systemImage: "eye")
            }
            NavigationLink {
                GrokTTSView(client: grokClient)
            } label: {
                Label("Text-to-Speech", systemImage: "speaker.wave.2")
            }
        }
    }

    private var grokClient: any GrokClientProtocol {
        // BaseHTTPClient default config picks up Config.apiBaseURL +
        // shared keychain tokens via the standard token provider wiring
        // upstream Linked Accounts ViewModel already runs against.
        GrokHTTPClient(client: BaseHTTPClient())
    }
}
