// LuminaVaultClient/LuminaVaultClient/Features/Settings/SettingsRootView.swift
//
// HER-212 — Settings root index. Currently surfaces:
//   * Privacy & Data (HER-212) — export + delete account.
//   * Advanced → Hermes Gateway (HER-218) — BYO Hermes pane.
// Future panes (theme, account, notifications, etc.) plug in as more rows.

import SwiftData
import SwiftUI

struct SettingsRootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            List {
                // HER-255 — Theme + light/dark switch at the top of Settings.
                LVAppearanceSection()

                // HER-39 — surface offline sync state + manual drain.
                Section("Sync & Backup") {
                    NavigationLink {
                        SyncBackupView()
                            .modelContainer(appState.modelContainer)
                    } label: {
                        Label("Sync & Backup", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

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

                // HER-247 / HER-178 — Skills hub (full detail) + Automations
                // (lightweight toggle list). Share the same SkillsHTTPClient.
                Section("Automation") {
                    NavigationLink {
                        SkillsHubView(
                            vm: SkillsHubViewModel(client: skillsClient),
                            detailClient: skillsClient
                        )
                    } label: {
                        Label("Skills", systemImage: "sparkles")
                    }
                    NavigationLink {
                        AutomationsView(vm: AutomationsViewModel(client: skillsClient))
                    } label: {
                        Label("Automations", systemImage: "clock.badge.checkmark")
                    }
                }

                // HER-179 — APNS category opt-out.
                Section("Notifications") {
                    NavigationLink {
                        NotificationsPaneView(vm: NotificationsPaneViewModel(client: apnsPrefsClient))
                    } label: {
                        Label("Notifications", systemImage: "bell.badge")
                    }
                }

                // HER-250 — backend mode + SOUL.md editor.
                Section("Server") {
                    NavigationLink {
                        ServerConnectionView(vm: ServerConnectionViewModel(soulClient: soulClient))
                    } label: {
                        Label("Server Connection", systemImage: "server.rack")
                    }
                }

                Section("Advanced") {
                    NavigationLink {
                        HermesGatewayPaneView(client: settingsClient)
                    } label: {
                        HStack {
                            Label("Hermes Gateway", systemImage: "network")
                            Spacer()
                            // HER-255 — connection status pill per issue spec.
                            // TODO: drive `state` from HermesGatewayViewModel when wired.
                            ConnectionBadge(state: .unknown)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var apnsPrefsClient: any APNSPrefsClientProtocol {
        APNSPrefsHTTPClient(client: appState.makeHTTPClient())
    }

    private var skillsClient: any SkillsClientProtocol {
        SkillsHTTPClient(client: appState.makeHTTPClient())
    }

    private var soulClient: any SoulClientProtocol {
        SoulHTTPClient(client: appState.makeHTTPClient())
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
