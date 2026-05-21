// LuminaVaultClient/LuminaVaultClient/Features/MainTabView.swift
// HER-35: replaces the mascot-only stub. The Spaces tab is the home view —
// other tabs (Capture, Visual Search, Settings) ride future tickets.
// HER-105: pass vault + memory query clients into SpacesListView so the
// three-pane browser (Spaces → Files → Reader) and the universal top
// search bar share the same auth-aware HTTP layer.
// HER-37: adds the 4th "Think" tab — natural-language query + memo flow.
// HER-VisualSearchWire: wires HER-157's VisualSearchView into the tab bar
// as the 4th tab. Reuses the existing memory-query HTTP client.
import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // HER-39 — pinned sync status. Hidden when idle.
                SyncStatusBanner()

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

                // HER-235: Brain tab — Obsidian-style memory graph.
                BrainTabView(client: memoryGraphClient)
                    .tabItem {
                        Label("Brain", systemImage: "brain.head.profile")
                    }

                // HER-177: Today tab — skill outputs feed.
                TodayView(vm: TodayViewModel(client: todayClient))
                    .tabItem {
                        Label("Today", systemImage: "newspaper.fill")
                    }

                // HER-157 surface wired by HER-VisualSearchWire.
                VisualSearchView(viewModel: VisualSearchViewModel(
                    ocr: ImageOCRService(),
                    client: memoryClient,
                    telemetry: LoggerTelemetry(),
                ))
                    .tabItem {
                        Label("Visual Search", systemImage: "photo.on.rectangle.angled")
                    }

                    // HER-212: Settings tab — Privacy & Data + Advanced (Hermes Gateway).
                    SettingsRootView()
                        .tabItem {
                            Label("Settings", systemImage: "gear")
                        }
                }
                .tint(.lvCyan)
            }

            // HER-34 — vault capture entry point. Floats above the tab
            // bar so it's reachable from any tab without stealing one.
            CaptureFAB()
                .padding(.trailing, 20)
                .padding(.bottom, 70)
        }
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

    private var memoryGraphClient: MemoryGraphClientProtocol {
        MemoryGraphHTTPClient(client: appState.makeHTTPClient())
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

    private var todayClient: TodayClientProtocol {
        TodayHTTPClient(client: appState.makeHTTPClient())
    }

    private var dashboardStatsClient: DashboardStatsClientProtocol {
        DashboardStatsHTTPClient(client: appState.makeHTTPClient())
    }

    private var tasksClient: TasksClientProtocol {
        TasksHTTPClient(client: appState.makeHTTPClient())
    }

    private var insightsClient: InsightsClientProtocol {
        InsightsHTTPClient(client: appState.makeHTTPClient())
    }

    private var healthClient: HealthClientProtocol {
        HealthHTTPClient()
    }

    private var home: some View {
        // HER-244 — OS Shell Home/Dashboard. Replaces the kb-compile-only
        // SyncAndLearnView with the real dashboard. Compile flow is
        // delegated to the existing SyncAndLearnViewModel + VaultRepository
        // so HER-39's offline queueing still applies.
        HomeView(
            vm: HomeViewModel(
                statsClient: dashboardStatsClient,
                tasksClient: tasksClient,
                insightsClient: insightsClient,
                healthClient: healthClient,
                compileViewModel: SyncAndLearnViewModel(repository: appState.vaultRepository),
                displayName: Self.deriveDisplayName(from: appState.currentEmail)
            ),
            onAskLumina: {
                // TODO(HER-245 / HER-107): when Sessions list + chat detail
                // ship, route to those surfaces directly. For now this is
                // a no-op — tapping defers to the Think tab via the tab bar.
            }
        )
    }

    private static func deriveDisplayName(from email: String?) -> String {
        guard let email, let at = email.firstIndex(of: "@") else { return "" }
        let local = email[..<at]
        let first = local.split(separator: ".").first.map(String.init) ?? String(local)
        return first.prefix(1).uppercased() + first.dropFirst()
    }
}
