// LuminaVaultClient/LuminaVaultClient/Features/Settings/SettingsRootView.swift
//
// HER-212 / HER-303 — Settings root index. Cinematic hero band +
// reusable `LVSectionCard` + `LVSettingsRow` components. Visual
// rebuild only; every destination view and the trial banner stay
// exactly where they were.

import SwiftData
import SwiftUI

struct SettingsRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.lvPalette) private var palette

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                RadialGradient(
                    colors: [palette.glowPrimary.opacity(0.15), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 600
                ).ignoresSafeArea()

                RadialGradient(
                    colors: [palette.accent.opacity(0.1), .clear],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: 500
                ).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: LVSpacing.xl) {
                        SettingsHeroBand()

                        // HER-211 — trial countdown banner.
                        TrialCountdownBanner()

                        // HER-255 — Theme + light/dark switch
                        LVSectionCard("Appearance") {
                            LVAppearanceSection()
                        }

                        // Phase 1 — post-onboarding SOUL.md personality editor.
                        // Phase 2 — direct memory browse/edit/delete.
                        LVSectionCard("Your Agent") {
                            LVSettingsRow("Personality", icon: .brainHeadProfile) {
                                SoulEditorView(client: soulClient, capabilities: hermesCapabilitiesClient)
                            }
                            LVSettingsDivider()
                            LVSettingsRow("Memories", icon: .brain) {
                                MemoryBrowserView(client: memoryClient)
                            }
                        }

                        LVSectionCard("Account & Data") {
                            LVSettingsRow("Sync & Backup", icon: .arrowTriangle2Circlepath) {
                                SyncBackupView()
                                    .modelContainer(appState.modelContainer)
                            }
                            LVSettingsDivider()
                            LVSettingsRow("Privacy & Data", icon: .lockShield) {
                                PrivacyDataView(
                                    viewModel: PrivacyDataViewModel(
                                        vaultClient: vaultClient,
                                        accountClient: accountClient,
                                        appState: appState
                                    ),
                                    securityViewModel: SecuritySettingsViewModel(keychain: appState.keychain)
                                )
                            }
                            LVSettingsDivider()
                            // Apple Ecosystem Integration P0 — per-domain data-access consent.
                            LVSettingsRow("Data Access", icon: .lockShield) {
                                DataAccessView(
                                    vm: DataAccessViewModel(
                                        client: AppleConsentHTTPClient(client: appState.makeHTTPClient())
                                    )
                                )
                            }
                        }

                        LVSectionCard("Connections") {
                            LVSettingsRow("Linked Accounts", icon: .linkCircle) {
                                LinkedAccountsView(client: integrationsClient)
                            }
                            LVSettingsDivider()
                            // HER-300/5 — renamed from "LLM Providers". The
                            // destination is now the Intelligence pane (Managed
                            // vs BYOK toggle + primary/fallback editor + nested
                            // "Manage API Keys" link into ProvidersPaneView).
                            LVSettingsRow("Intelligence", icon: .brain) {
                                LLMPreferencesPaneView(
                                    client: llmPreferencesClient,
                                    providersClient: providersClient
                                )
                            }
                            LVSettingsDivider()
                            // HER-218 — "Bring Your Own Hermes". Promoted from
                            // System & Advanced so the Managed-vs-connect-your-own
                            // choice sits next to Intelligence. Renamed from
                            // "Hermes Gateway" to disambiguate from the HER-241
                            // "Messaging Gateways" pane below.
                            LVSettingsRow(
                                "Hermes Server",
                                icon: .network,
                                trailing: { ConnectionBadge(state: .unknown) },
                                destination: { HermesGatewayPaneView(client: settingsClient) }
                            )
                            LVSettingsDivider()
                            // Nous Subscription Integration — connect a personal
                            // Nous Portal subscription (OAuth device-code) so
                            // Hermes runs on the user's own credits.
                            LVSettingsRow("Connect Nous Account", icon: .sparkles) {
                                NousAccountView(client: integrationsClient)
                            }
                            LVSettingsDivider()
                            // HER-43 — declarative plugin store (connectors, …).
                            LVSettingsRow("Plugins", icon: .puzzlepieceExtension) {
                                PluginStoreView(client: pluginsClient)
                            }
                            LVSettingsDivider()
                            // Import an Obsidian/Hermes vault folder → Spaces +
                            // Brain graph + grounding (POST /v1/import/vault-bulk).
                            LVSettingsRow("Import Vault", icon: .trayAndArrowDown) {
                                VaultImportView(client: VaultImportHTTPClient(client: appState.makeHTTPClient()))
                            }
                            LVSettingsDivider()
                            // TUI-parity: list the connected Hermes's cron jobs
                            // (managed exec or BYO dashboard API).
                            LVSettingsRow("Hermes Cron", icon: .arrowClockwiseCircle) {
                                HermesCronListView(client: HermesCronHTTPClient(client: appState.makeHTTPClient()))
                            }
                        }

                        LVSectionCard("Automation & Alerts") {
                            LVSettingsRow("Skills", icon: .sparkles) {
                                SkillsHubView(
                                    vm: SkillsHubViewModel(client: skillsClient),
                                    detailClient: skillsClient
                                )
                            }
                            LVSettingsDivider()
                            LVSettingsRow("Automations", icon: .clockBadgeCheckmark) {
                                AutomationsView(vm: AutomationsViewModel(client: skillsClient))
                            }
                            LVSettingsDivider()
                            LVSettingsRow("Notifications", icon: .bellBadge) {
                                NotificationsPaneView(
                                    vm: NotificationsPaneViewModel(client: apnsPrefsClient)
                                )
                            }
                        }

                        LVSectionCard("App") {
                            LVSettingsRow("Subscription", icon: .creditcard) {
                                SubscriptionView()
                            }
                            LVSettingsDivider()
                            LVSettingsRow("About LuminaVault", icon: .infoCircle) {
                                AboutView()
                            }
                        }

                        LVSectionCard("System & Advanced") {
                            LVSettingsRow("Server Connection", icon: .serverRack) {
                                ServerConnectionView(vm: ServerConnectionViewModel(soulClient: soulClient))
                            }
                            LVSettingsDivider()
                            // Phase 1 — read-only "is my agent alive + how is
                            // it wired" snapshot over existing endpoints.
                            LVSettingsRow("Diagnostics", icon: .shieldBrain) {
                                HermesDiagnosticsView(
                                    llmClient: llmPreferencesClient,
                                    providersClient: providersClient,
                                    integrationsClient: integrationsClient,
                                    settingsClient: settingsClient
                                )
                            }
                            LVSettingsDivider()
                            // HER-218 "Hermes Server" moved up to Connections.
                            LVSettingsRow("Messaging Gateways", icon: .bubbleLeftAndBubbleRight) {
                                HermesGatewaysPaneView(client: hermesGatewaysClient)
                            }
                            LVSettingsDivider()
                            // HER-330 — owner-only Hermes self-update.
                            LVSettingsRow("Update Hermes", icon: .trayAndArrowDown) {
                                HermesUpdateView(client: systemHermesClient)
                            }
                            LVSettingsDivider()
                            // HER — approve a browser session for the web dashboard
                            // by scanning the QR shown on the LuminaVault website.
                            LVSettingsRow("Approve Web Sign-In", icon: .door) {
                                WebSignInApprovalView(client: appState.makeHTTPClient())
                            }
                            // HER-300/5 — "Model Preferences" was folded into
                            // the new "Intelligence" row under Connections.
                        }
                    }
                    .padding(.horizontal, LVSpacing.lg)
                    .padding(.top, LVSpacing.xl)
                    .padding(.bottom, LVSpacing.hero + LVSpacing.xxl)
                }
            }
            // HER-255 — header hoisted to MainTabView (app-wide base header).
            .lvBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Client wiring (mirrors MainTabView's per-tab factories)

    private var apnsPrefsClient: any APNSPrefsClientProtocol {
        APNSPrefsHTTPClient(client: appState.makeHTTPClient())
    }

    // HER-330 — owner-only Hermes self-update client.
    private var systemHermesClient: SystemHermesHTTPClient {
        SystemHermesHTTPClient(client: appState.makeHTTPClient())
    }

    private var skillsClient: any SkillsClientProtocol {
        SkillsHTTPClient(client: appState.makeHTTPClient())
    }

    private var soulClient: any SoulClientProtocol {
        SoulHTTPClient(client: appState.makeHTTPClient())
    }

    private var hermesCapabilitiesClient: any HermesCapabilitiesClientProtocol {
        HermesCapabilitiesHTTPClient(client: appState.makeHTTPClient())
    }

    private var memoryClient: any MemoryClientProtocol {
        MemoryHTTPClient(client: appState.makeHTTPClient())
    }

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

    // HER-252 — per-user LLM provider credentials + routing preferences.
    private var providersClient: any ProvidersClientProtocol {
        ProvidersHTTPClient(client: appState.makeHTTPClient())
    }

    private var llmPreferencesClient: any LLMPreferencesClientProtocol {
        LLMPreferencesHTTPClient(client: appState.makeHTTPClient())
    }

    // HER-241 — per-user Hermes messaging gateway configurator.
    private var hermesGatewaysClient: any HermesGatewaysClientProtocol {
        HermesGatewaysHTTPClient(client: appState.makeHTTPClient())
    }

    // HER-43 — declarative plugin foundation (catalog + installs + sync).
    private var pluginsClient: any PluginsClientProtocol {
        PluginsHTTPClient(client: appState.makeHTTPClient())
    }
}
