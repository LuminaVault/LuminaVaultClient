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
    @Environment(\.lvPalette) private var palette

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Cosmic Background
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
                    VStack(spacing: 24) {
                        // HER-211 — trial countdown banner.
                        TrialCountdownBanner()
                            .padding(.top, 10)

                        // HER-255 — Theme + light/dark switch
                        glassSection(title: "Appearance") {
                            LVAppearanceSection()
                        }

                        // Sync & Privacy
                        glassSection(title: "Account & Data") {
                            settingsRow(
                                title: "Sync & Backup",
                                icon: "arrow.triangle.2.circlepath",
                                destination: AnyView(SyncBackupView().modelContainer(appState.modelContainer))
                            )
                            settingsDivider
                            settingsRow(
                                title: "Privacy & Data",
                                icon: "lock.shield",
                                destination: AnyView(PrivacyDataView(
                                    viewModel: PrivacyDataViewModel(
                                        vaultClient: vaultClient,
                                        accountClient: accountClient,
                                        appState: appState
                                    ),
                                    securityViewModel: SecuritySettingsViewModel(keychain: appState.keychain)
                                ))
                            )
                        }

                        // Connections
                        glassSection(title: "Connections") {
                            settingsRow(
                                title: "Linked Accounts",
                                icon: "link.circle",
                                destination: AnyView(LinkedAccountsView(client: integrationsClient))
                            )
                            settingsDivider
                            settingsRow(
                                title: "LLM Providers",
                                icon: "brain",
                                destination: AnyView(ProvidersPaneView(client: providersClient))
                            )
                        }

                        // Automation & Notifications
                        glassSection(title: "Automation & Alerts") {
                            settingsRow(
                                title: "Skills",
                                icon: "sparkles",
                                destination: AnyView(SkillsHubView(vm: SkillsHubViewModel(client: skillsClient), detailClient: skillsClient))
                            )
                            settingsDivider
                            settingsRow(
                                title: "Automations",
                                icon: "clock.badge.checkmark",
                                destination: AnyView(AutomationsView(vm: AutomationsViewModel(client: skillsClient)))
                            )
                            settingsDivider
                            settingsRow(
                                title: "Notifications",
                                icon: "bell.badge",
                                destination: AnyView(NotificationsPaneView(vm: NotificationsPaneViewModel(client: apnsPrefsClient)))
                            )
                        }

                        // Subscription & About
                        glassSection(title: "App") {
                            settingsRow(
                                title: "Subscription",
                                icon: "creditcard",
                                destination: AnyView(SubscriptionView())
                            )
                            settingsDivider
                            settingsRow(
                                title: "About LuminaVault",
                                icon: "info.circle",
                                destination: AnyView(AboutView())
                            )
                        }

                        // Server & Advanced
                        glassSection(title: "System & Advanced") {
                            settingsRow(
                                title: "Server Connection",
                                icon: "server.rack",
                                destination: AnyView(ServerConnectionView(vm: ServerConnectionViewModel(soulClient: soulClient)))
                            )
                            settingsDivider
                            
                            // Hermes Gateway with connection badge
                            NavigationLink {
                                HermesGatewayPaneView(client: settingsClient)
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "network")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(palette.glowPrimary)
                                        .frame(width: 24)
                                    Text("Hermes Gateway")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(palette.textPrimary)
                                    Spacer()
                                    ConnectionBadge(state: .unknown)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.textSecondary.opacity(0.5))
                                }
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            settingsDivider
                            settingsRow(
                                title: "Messaging Gateways",
                                icon: "bubble.left.and.bubble.right",
                                destination: AnyView(HermesGatewaysPaneView(client: hermesGatewaysClient))
                            )
                            settingsDivider
                            settingsRow(
                                title: "Model Preferences",
                                icon: "slider.horizontal.3",
                                destination: AnyView(LLMPreferencesPaneView(client: llmPreferencesClient))
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 40)
                    .padding(.bottom, 140)
                }
            }
            .safeAreaInset(edge: .top) {
                LuminaHeader(title: "Settings")
            }
            .lvBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var headerSection: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .shadow(color: palette.glowPrimary.opacity(0.8), radius: 12)
            Spacer()
        }
    }

    private func glassSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
                .tracking(2)
                .padding(.leading, 8)
            
            VStack(spacing: 0) {
                content()
            }
            .lvGlassCard(cornerRadius: 24, intensity: 0.5)
        }
    }

    private func settingsRow(title: String, icon: String, destination: AnyView) -> some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(palette.glowPrimary)
                    .frame(width: 24)
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary.opacity(0.5))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var settingsDivider: some View {
        Divider()
            .background(palette.surfaceStroke)
            .padding(.leading, 56)
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
}
