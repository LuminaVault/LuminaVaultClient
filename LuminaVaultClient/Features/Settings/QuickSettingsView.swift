// LuminaVaultClient/LuminaVaultClient/Features/Settings/QuickSettingsView.swift
//
// Compact "Quick Settings" surface presented from the header mascot avatar
// (LuminaHeader.onMascotTap). The full Settings index still lives behind the
// "..." (More) tab — this is a fast-access shortcut to the handful of settings
// used most often. Each row pushes the *same* destination view the full
// Settings screen uses, so there is a single source of truth per pane.
//
// Client wiring mirrors SettingsRootView's per-pane factories (all built off
// `appState.makeHTTPClient()`).
import SwiftUI

struct QuickSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.lvPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LVSpacing.lg) {
                    // Most-used setting: theme. Reuses the exact Auto/Light/Dark
                    // control from the full Settings screen.
                    LVSectionCard("Appearance") {
                        LVAppearanceSection()
                    }

                    // Headline action — same Sync & Learn flow as Home.
                    syncAndLearnCTA

                    LVSectionCard("Your Brain") {
                        LVSettingsRow("LLM Brain", icon: .brain) {
                            intelligenceDestination
                        }
                        LVSettingsDivider()
                        LVSettingsRow("Hermes", icon: .network) {
                            hermesUpdateDestination
                        }
                    }

                    LVSectionCard("Capture") {
                        // Client Import UI not built yet (Feed Your Brain P1 is
                        // server-only; EventKitImportService exists but has no
                        // presentable screen). Slot reserved as coming-soon.
                        LVSettingsRow("Import from iPhone", icon: .trayAndArrowDown) {
                            ComingSoonPane(feature: "Import from iPhone")
                        }
                    }

                    LVSectionCard("Account") {
                        LVSettingsRow("Account", icon: .lockShield) {
                            accountDestination
                        }
                    }

                    LVSectionCard("More") {
                        LVSettingsRow("Full Settings", icon: .tabSettings) {
                            SettingsRootView()
                        }
                    }
                }
                .padding(.horizontal, LVSpacing.lg)
                .padding(.vertical, LVSpacing.lg)
            }
            .lvBackground()
            .navigationTitle("Quick Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sync & Learn glow CTA

    private var syncAndLearnCTA: some View {
        NavigationLink {
            syncAndLearnDestination
        } label: {
            HStack(spacing: LVSpacing.base) {
                LVIconView(.sparkles, size: 24, tint: .white, weight: .bold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync & Learn")
                        .font(LVTypography.headline.font.weight(.heavy))
                    Text("Compile new captures into your brain")
                        .font(LVTypography.caption.font)
                        .opacity(0.9)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            .padding(LVSpacing.lg)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: LVRadius.card, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [palette.glowPrimary, palette.secondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .shadow(color: palette.glowPrimary.opacity(0.5), radius: 18)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Destinations (mirror SettingsRootView / MainTabView wiring)

    private var intelligenceDestination: some View {
        LLMPreferencesPaneView(
            client: LLMPreferencesHTTPClient(client: appState.makeHTTPClient()),
            providersClient: ProvidersHTTPClient(client: appState.makeHTTPClient())
        )
    }

    private var hermesUpdateDestination: some View {
        HermesUpdateView(
            client: SystemHermesHTTPClient(client: appState.makeHTTPClient())
        )
    }

    private var syncAndLearnDestination: some View {
        SyncAndLearnView(
            vm: SyncAndLearnViewModel(
                repository: appState.vaultRepository,
                pendingClient: appState.makeKBCompileClient(),
                webSocket: appState.makeKBCompileWebSocketClient(),
                memoryClient: appState.makeMemoryClient()
            )
        )
    }

    private var accountDestination: some View {
        PrivacyDataView(
            viewModel: PrivacyDataViewModel(
                vaultClient: VaultHTTPClient(client: appState.makeHTTPClient()),
                accountClient: AccountHTTPClient(client: appState.makeHTTPClient()),
                appState: appState
            ),
            securityViewModel: SecuritySettingsViewModel(keychain: appState.keychain)
        )
    }
}

// MARK: - Coming soon placeholder

private struct ComingSoonPane: View {
    @Environment(\.lvPalette) private var palette
    let feature: String

    var body: some View {
        VStack(spacing: LVSpacing.base) {
            Image(systemName: "hourglass")
                .font(.largeTitle)
                .foregroundStyle(palette.glowPrimary)
            Text(feature)
                .font(LVTypography.title.font)
            Text("Coming soon.")
                .font(LVTypography.callout.font)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
        .navigationTitle(feature)
        .navigationBarTitleDisplayMode(.inline)
    }
}
