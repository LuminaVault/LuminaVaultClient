// LuminaVaultClient/LuminaVaultClient/Features/MainTabView.swift
// HER-35: replaces the mascot-only stub. The Spaces tab is the home view —
// other tabs (Capture, Visual Search, Settings) ride future tickets.
// HER-105: pass vault + memory query clients into SpacesListView so the
// three-pane browser (Spaces → Files → Reader) and the universal top
// search bar share the same auth-aware HTTP layer.
// HER-37: adds the 4th "Think" tab — natural-language query + memo flow.
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

            // HER-37: Think tab — "Think with Lumina" + memo flow.
            ThinkWithLuminaView(
                vm: ThinkWithLuminaViewModel(
                    queryClient: memoryClient,
                    suggestionsClient: suggestionsClient,
                ),
                memoClient: memoClient,
            )
                .tabItem {
                    Label("Think", systemImage: "bubble.left.and.text.bubble.right")
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
        SpacesHTTPClient(client: appState.makeHTTPClient())
    }

    private var vaultClient: VaultClientProtocol {
        VaultHTTPClient(client: appState.makeHTTPClient())
    }

    private var memoryClient: MemoryQueryClientProtocol {
        MemoryQueryHTTPClient(client: appState.makeHTTPClient())
    }

    private var kbCompileClient: KBCompileClientProtocol {
        KBCompileHTTPClient(client: appState.makeHTTPClient())
    }

    private var memoClient: MemoClientProtocol {
        MemoHTTPClient(client: appState.makeHTTPClient())
    }

    private var suggestionsClient: SuggestionsClientProtocol {
        SuggestionsHTTPClient(client: appState.makeHTTPClient())
    }

    private var home: some View {
        SyncAndLearnView(vm: SyncAndLearnViewModel(client: kbCompileClient))
    }
}
