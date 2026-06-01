// LuminaVaultClient/LuminaVaultClient/Features/MainTabView.swift
// HER-35: replaces the mascot-only stub. The Spaces tab is the home view —
// other tabs (Capture, Visual Search, Settings) ride future tickets.
// HER-105: pass vault + memory query clients into SpacesListView so the
// three-pane browser (Spaces → Files → Reader) and the universal top
// search bar share the same auth-aware HTTP layer.
// HER-37: adds the 4th "Think" tab — natural-language query + memo flow.
// HER-VisualSearchWire: wires HER-157's VisualSearchView into the tab bar
// as the 4th tab. Reuses the existing memory-query HTTP client.
// HER-255: replaces the stock TabView chrome with LVTabBar (glass background
// + glowing underline on the active tab + pulse on Home when insights pend).
// HER-243: trims the bar to 5 tabs (Spaces · Home · Think · Memory · Settings),
// re-anchors CaptureFAB to the bar centre, and floats HermieMascotView above
// the FAB. Today + VisualSearch surfaces move into Home dashboard cards
// (HER-244 already accepts the AnyView destinations).
import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var selection: String = "home"
    @State private var hermieState: HermieMascotState = .idle
    @Namespace private var tabUnderline

    private static let tabIds = (
        workspaces: "workspaces",
        home: "home",
        reflect: "reflect",
        think: "think",
        brain: "brain",
        settings: "settings"
    )

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // HER-39 — pinned sync status. Hidden when idle.
                SyncStatusBanner()

                TabView(selection: $selection) {
                    // HER-249 — Workspaces wraps Spaces with workspace-aware
                    // chrome. Underlying file/folder UI is unchanged for v1.
                    WorkspacesView(
                        vm: SpacesViewModel(spacesClient: spacesClient),
                        vaultClient: vaultClient,
                        memoryClient: memoryClient,
                        memoryDetailClient: memoryUpsertClient,
                        uploadClient: vaultUploadClient,
                    )
                    .tag(Self.tabIds.workspaces)
                    .toolbar(.hidden, for: .tabBar)

                    home
                        .tag(Self.tabIds.home)
                        .toolbar(.hidden, for: .tabBar)

                    // HER-194 — Reflect tab. Synth-cluster skills
                    // (Patterns / Contradictions / Beliefs) with topic
                    // input, full-screen result + Save-to-Vault.
                    reflect
                        .tag(Self.tabIds.reflect)
                        .toolbar(.hidden, for: .tabBar)

                    // HER-107: Think tab — multi-turn chat. Memory-grounded
                    // mode streams over SSE; fresh mode hits
                    // /v1/chat/completions. Both routes are BYO-Hermes-aware
                    // server-side.
                    ThinkWithLuminaView(
                        chatVM: ChatViewModel(
                            conversationsClient: conversationsClient,
                            chatClient: chatClient,
                            memoryClient: memoryUpsertClient,
                            historyStore: chatHistoryStore,
                        ),
                        memoClient: memoClient,
                        suggestionsClient: suggestionsClient,
                        vaultClient: vaultClient,
                        memoryClient: memoryUpsertClient,
                        vaultUploadClient: vaultUploadClient,
                    )
                    .tag(Self.tabIds.think)
                    .toolbar(.hidden, for: .tabBar)

                    // HER-212: Settings tab — Privacy & Data + Advanced (Hermes Gateway).
                    SettingsRootView()
                        .tag(Self.tabIds.settings)
                        .toolbar(.hidden, for: .tabBar)

                    VisualSearchView(viewModel: VisualSearchViewModel(
                        ocr: ImageOCRService(),
                        client: memoryClient,
                        telemetry: LoggerTelemetry(),
                    ))
                    .tag("visual_search")
                    .toolbar(.hidden, for: .tabBar)
                }
            }

            // HER-107 — primary 3 (Home / Think / Spaces) + More overflow
            // (Settings / Memory). HER-243's FAB sits centred over the bar
            // anchored via the VStack below.
            LVTabBar(
                primaryItems: primaryTabItems,
                overflowItems: overflowTabItems,
                overflowLeading: true,
                selection: $selection,
                underlineNamespace: tabUnderline,
            )

            // HER-243 — capture FAB anchored centrally over the tab bar.
            // Hidden on the AI tab: the chat composer owns the bottom edge,
            // and the FAB would float on top of the text field + send button.
            if selection != Self.tabIds.think {
                CaptureFAB()
                    .padding(.bottom, 70)
            }
        }
        .onChange(of: selection) { _, newValue in
            // HER-243 — drive Hermie state from the active tab. ".thinking"
            // for Think tab; calm idle elsewhere. Streaming-aware sub-state
            // wiring lands when ThinkWithLuminaViewModel exposes its phase
            // via the AppState observation tree.
            hermieState = (newValue == Self.tabIds.think) ? .thinking : .idle
        }
    }

    // HER-107: tab bar split per Apple HIG — 3 primary tabs + More
    // overflow. Home / Think / Spaces are the daily-driver surfaces;
    // Settings / Visual Search live behind More.
    // HER-291: tab icons resolve via `LVIcon`; the `.tab*` cases carry
    // their `Lumina/Tab/*` branded asset paths.
    private var primaryTabItems: [LVTabItem] {
        [
            LVTabItem(id: Self.tabIds.workspaces, label: "Spaces", icon: .tabSpaces),
            LVTabItem(id: Self.tabIds.home, label: "Home", icon: .tabHome),
            // HER-194 — Reflect lives between Home and Think; the
            // synthesis-intelligence cluster is the premium-flawless
            // surface that justifies a primary tab.
            LVTabItem(id: Self.tabIds.reflect, label: "Reflect", icon: .sparklesRectangleStack),
            LVTabItem(id: Self.tabIds.think, label: "AI", icon: .tabThink),
        ]
    }

    private var overflowTabItems: [LVTabItem] {
        [
            LVTabItem(id: "visual_search", label: "Visual Search", icon: .photoOnRectangleAngled),
            LVTabItem(id: Self.tabIds.settings, label: "Settings", icon: .tabSettings),
        ]
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

    // HER-107 — Conversations client wraps the shared BaseHTTPClient so
    // streaming chat shares the bearer + 401 refresh coordinator.
    private var conversationsClient: any ConversationsClientProtocol {
        appState.makeConversationsClient()
    }

    // HER-107 — non-streaming chat client (Hermes "fresh" mode).
    private var chatClient: any ChatClientProtocol {
        appState.makeChatClient()
    }

    // HER-107 — memory write-side client for long-press save-to-memory
    // (distinct from read-side `memoryClient`, which only queries).
    private var memoryUpsertClient: any MemoryClientProtocol {
        MemoryHTTPClient(client: appState.makeHTTPClient())
    }

    // HER-107 — persisted chat history (last 50 turns) keyed by
    // conversation id. Shared actor lives in App Group container so the
    // share extension can later seed conversations from outside the
    // host app.
    private var chatHistoryStore: ChatHistoryStore {
        ChatHistoryStore()
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

    private var dashboardProfileClient: DashboardProfileClientProtocol {
        DashboardProfileHTTPClient(client: appState.makeHTTPClient())
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
                profileClient: dashboardProfileClient,
                tasksClient: tasksClient,
                insightsClient: insightsClient,
                healthClient: healthClient,
                compileViewModel: SyncAndLearnViewModel(
                    repository: appState.vaultRepository,
                    pendingClient: appState.makeKBCompileClient(),
                    webSocket: appState.makeKBCompileWebSocketClient(),
                    memoryClient: appState.makeMemoryClient(),
                ),
                displayName: Self.deriveDisplayName(from: appState.currentEmail),
                homeClient: HomeSummaryHTTPClient(client: appState.makeHTTPClient()),
                analyticsClient: AnalyticsHTTPClient(client: appState.makeHTTPClient())
            ),
            onAskLumina: {
                // TODO(HER-107): when chat detail ships, route to it
                // directly. For now defers to the Think tab.
            },
            onSelectTab: { selection = $0 },
            sessionsDestination: AnyView(
                SessionsListView(vm: SessionsListViewModel(client: sessionsClient))
            ),
            tasksDestination: AnyView(
                TasksListView(vm: TasksListViewModel(client: tasksClient))
            ),
            insightsDestination: AnyView(
                InsightsListView(vm: InsightsListViewModel(client: insightsClient))
            ),
            serverConnectionDestination: AnyView(
                ServerConnectionView(vm: ServerConnectionViewModel(soulClient: soulClient))
            ),
            skillsDestination: AnyView(
                SkillsHubView(
                    vm: SkillsHubViewModel(client: skillsClient),
                    detailClient: skillsClient,
                )
            ),
            todayDestination: AnyView(
                TodayView(
                    vm: TodayViewModel(client: todayClient),
                    vaultClient: vaultClient,
                    memoryClient: memoryUpsertClient,
                )
            ),
            visualSearchDestination: AnyView(
                VisualSearchView(viewModel: VisualSearchViewModel(
                    ocr: ImageOCRService(),
                    client: memoryClient,
                    telemetry: LoggerTelemetry(),
                ))
            ),
            healthDestination: AnyView(
                HealthDashboardScreen(
                    httpClient: appState.makeHTTPClient(),
                    coordinator: appState.healthKit,
                )
            ),
        )
    }

    private var skillsClient: SkillsClientProtocol {
        SkillsHTTPClient(client: appState.makeHTTPClient())
    }

    // HER-194 — vault upload client wired so Save-to-Vault in Reflect
    // can POST the cached rendered markdown without firing a second
    // LLM call.
    private var vaultUploadClient: VaultUploadClientProtocol {
        VaultUploadHTTPClient(client: appState.makeHTTPClient())
    }

    private var reflect: some View {
        ReflectTabView(
            vm: ReflectViewModel(vaultClient: vaultClient),
            runner: ReflectionRunner(
                skillsClient: skillsClient,
                vaultUploadClient: vaultUploadClient,
            ),
            vaultClient: vaultClient,
            memoryClient: memoryUpsertClient,
        )
    }

    private var sessionsClient: SessionsClientProtocol {
        SessionsHTTPClient(client: appState.makeHTTPClient())
    }

    private var soulClient: SoulClientProtocol {
        SoulHTTPClient(client: appState.makeHTTPClient())
    }

    private static func deriveDisplayName(from email: String?) -> String {
        guard let email, let at = email.firstIndex(of: "@") else { return "" }
        let local = email[..<at]
        let first = local.split(separator: ".").first.map(String.init) ?? String(local)
        return first.prefix(1).uppercased() + first.dropFirst()
    }
}
