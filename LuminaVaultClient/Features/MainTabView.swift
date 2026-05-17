// LuminaVaultClient/LuminaVaultClient/Features/MainTabView.swift
// HER-35: replaces the mascot-only stub. The Spaces tab is the home view —
// other tabs (Capture, Visual Search, Settings) ride future tickets.
// HER-105: pass vault + memory query clients into SpacesListView so the
// three-pane browser (Spaces → Files → Reader) and the universal top
// search bar share the same auth-aware HTTP layer.
import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            SpacesListView(
                vm: SpacesViewModel(spacesClient: spacesClient),
                vaultClient: vaultClient,
                memoryClient: memoryClient,
            )
                .tabItem {
                    Label("Spaces", systemImage: "folder.fill")
                }

            home
                .tabItem {
                    Label("Home", systemImage: "sparkles")
                }

            // HER-212: Settings tab — Privacy & Data + Advanced (Hermes Gateway).
            SettingsRootView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .tint(.lvCyan)
    }

    private var spacesClient: SpacesClientProtocol {
        SpacesHTTPClient(client: BaseHTTPClient(
            tokenProvider: { [appState] in appState.keychain.accessToken }
        ))
    }

    private var vaultClient: VaultClientProtocol {
        VaultHTTPClient(client: BaseHTTPClient(
            tokenProvider: { [appState] in appState.keychain.accessToken }
        ))
    }

    private var memoryClient: MemoryQueryClientProtocol {
        MemoryQueryHTTPClient(client: BaseHTTPClient(
            tokenProvider: { [appState] in appState.keychain.accessToken }
        ))
    }

    private var kbCompileClient: KBCompileClientProtocol {
        KBCompileHTTPClient(client: BaseHTTPClient(
            tokenProvider: { [appState] in appState.keychain.accessToken }
        ))
    }

    private var home: some View {
        SyncAndLearnView(vm: SyncAndLearnViewModel(client: kbCompileClient))
    }
}
