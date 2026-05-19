// LuminaVaultClient/LuminaVaultClient/Features/Settings/SettingsRootView.swift
//
// HER-212 — Settings root index. Currently surfaces:
//   * Privacy & Data (HER-212) — export + delete account.
//   * Advanced → Hermes Gateway (HER-218) — BYO Hermes pane.
// Future panes (theme, account, notifications, etc.) plug in as more rows.

import SwiftUI

struct SettingsRootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            List {
                Section("Privacy & Data") {
                    NavigationLink {
                        PrivacyDataView(viewModel: PrivacyDataViewModel(
                            vaultClient: vaultClient,
                            accountClient: accountClient,
                            appState: appState
                        ))
                    } label: {
                        Label("Privacy & Data", systemImage: "lock.shield")
                    }
                }

                Section("Connections") {
                    NavigationLink {
                        LinkedAccountsView(client: integrationsClient)
                    } label: {
                        Label("Linked Accounts", systemImage: "link.circle")
                    }
                }

                Section("Advanced") {
                    NavigationLink {
                        HermesGatewayPaneView(client: settingsClient)
                    } label: {
                        Label("Hermes Gateway", systemImage: "network")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Client wiring (mirrors MainTabView's per-tab factories)

    private var vaultClient: any VaultClientProtocol {
        VaultHTTPClient(client: appState.makeHTTPClient())
    }

    private var accountClient: any AccountClientProtocol {
        AccountHTTPClient(client: appState.makeHTTPClient())
    }

    private var settingsClient: any SettingsClientProtocol {
        SettingsHTTPClient(client: appState.makeHTTPClient())
    }

    private var integrationsClient: any IntegrationsClientProtocol {
        IntegrationsHTTPClient(client: appState.makeHTTPClient())
    }
}
