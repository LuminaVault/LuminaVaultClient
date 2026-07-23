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
    @Environment(NotificationRouter.self) private var notificationRouter
    @State private var selection: String = "home"
    @State private var hermieState: HermieMascotState = .idle
    // HER-255 — QuickSettings now opens from the global header's mascot tap
    // (was owned by HomeView's per-screen header).
    @State private var showQuickSettings = false
    @State private var tabBarHeight: CGFloat = LVTabBarHeightKey.defaultValue
    @Namespace private var tabUnderline
    @AppStorage("lv.chat.hapticsEnabled") private var hapticsEnabled = true
    @State private var tabHapticTrigger = 0

    private static let tabIds = (
        workspaces: "workspaces",
        home: "home",
        reflect: "reflect",
        think: "think",
        brain: "brain",
        settings: "settings"
    )
    private static let studioTabID = "studio"

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // HER-39 — pinned sync status. Hidden when idle.
                SyncStatusBanner()

                // HER-255 — global app header (the "base of the app"). Lives
                // above the TabView so it's present on every tab and every
                // pushed detail. Per-screen LuminaHeaders were removed; the
                // title is derived from the active tab. The compact capture
                // "+" rides inside LuminaHeader.
                LuminaHeader(
                    title: currentTitle,
                    mascotState: hermieState,
                    onMascotTap: { showQuickSettings = true }
                )

                // HER-fix — overflow destinations (Settings / Visual Search)
                // live OUTSIDE the TabView. A SwiftUI `TabView` on iPhone
                // buckets the 6th+ tab into the system "More" list
                // (`UIMoreListController`), which `.toolbar(.hidden,for:.tabBar)`
                // does NOT suppress — that produced the blank "More" screen and
                // the double back-chevron (More's own nav controller wrapping
                // the app's NavigationStack). Keeping the TabView at exactly 5
                // primary tabs avoids the overflow entirely. The overflow views
                // are swapped in as siblings so the primary TabView is fully
                // removed from the hierarchy while they're shown — which lets
                // Brain's `onAppear/onDisappear` pause fire correctly.
                if Self.isOverflow(selection) {
                    overflowDestination
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Clear the floating glass tab bar so content isn't
                        // hidden behind the capsule.
                        .safeAreaPadding(.bottom, tabBarHeight)
                } else {
                    TabView(selection: $selection) {
                        // HER-249 — Workspaces wraps Spaces with workspace-aware
                        // chrome. Underlying file/folder UI is unchanged for v1.
                        WorkspacesView(
                            vm: SpacesViewModel(spacesClient: spacesClient),
                            vaultClient: vaultClient,
                            memoryClient: memoryClient,
                            memoryDetailClient: memoryUpsertClient,
                            uploadClient: vaultUploadClient,
                            teamClient: TeamHTTPClient(client: appState.makeHTTPClient()),
                            activeVaultStore: appState.activeVaultStore
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

                        // HER-235 — Brain tab. The Obsidian-style knowledge
                        // graph. Re-surfaced as a primary tab after the HER-243
                        // OS-shell rebuild dropped it from the bar (the view +
                        // client survived, only the nav wiring was lost).
                        BrainTabView(
                            client: memoryGraphClient,
                            knowledgeClient: knowledgeGraphClient,
                            memoryClient: memoryUpsertClient
                        )
                        .tag(Self.tabIds.brain)
                        .toolbar(.hidden, for: .tabBar)

                        // HER-107: Think tab — multi-turn chat. Memory-grounded
                        // mode streams over SSE; fresh mode hits
                        // /v1/chat/completions. Both routes are BYO-Hermes-aware
                        // server-side.
                        ThinkWithLuminaView(
                            chatVM: makeChatViewModel(),
                            conversationsClient: conversationsClient,
                            chatExperienceClient: chatExperienceClient,
                            memoClient: memoClient,
                            suggestionsClient: suggestionsClient,
                            vaultClient: vaultClient,
                            memoryClient: memoryUpsertClient,
                            vaultUploadClient: vaultUploadClient
                        )
                        .tag(Self.tabIds.think)
                        .toolbar(.hidden, for: .tabBar)
                    }
                    // Clear the floating glass tab bar so page content isn't
                    // hidden behind the capsule.
                    .safeAreaPadding(.bottom, tabBarHeight)
                }
            }

            // HER-107 — primary 3 (Home / Think / Spaces) + More overflow
            // (Settings / Memory). HER-243's FAB sits centred over the bar
            // anchored via the VStack below.
            LVTabBar(
                primaryItems: primaryTabItems,
                overflowItems: overflowTabItems,
                overflowLeading: false,
                selection: $selection,
                underlineNamespace: tabUnderline
            )
            // HER-255 — capture "+" moved into LuminaHeader (compact style);
            // the floating FAB over the tab bar is retired.
        }
        .onPreferenceChange(LVTabBarHeightKey.self) { tabBarHeight = $0 }
        .onChange(of: selection) { oldValue, newValue in
            if oldValue != newValue, hapticsEnabled {
                tabHapticTrigger += 1
            }
            // HER-243 — drive Hermie state from the active tab. ".thinking"
            // for Think tab; calm idle elsewhere. Streaming-aware sub-state
            // wiring lands when ThinkWithLuminaViewModel exposes its phase
            // via the AppState observation tree.
            hermieState = (newValue == Self.tabIds.think) ? .thinking : .idle
        }
        .onChange(of: appState.pendingChatConversationID) { _, conversationID in
            guard conversationID != nil else { return }
            selection = Self.tabIds.think
        }
        .onChange(of: notificationRouter.pendingDeepLink) { _, deepLink in
            if case .workflow = deepLink {
                selection = Self.studioTabID
            }
        }
        .sheet(isPresented: $showQuickSettings) {
            QuickSettingsView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.selection, trigger: tabHapticTrigger)
    }

    /// HER-255 — global header title per active tab.
    private var currentTitle: String {
        switch selection {
        case Self.tabIds.workspaces: return "Spaces"
        case Self.tabIds.home: return "LuminaVault"
        case Self.tabIds.reflect: return "Insights"
        case Self.tabIds.think: return "AI"
        case Self.tabIds.brain: return "Brain"
        case Self.tabIds.settings: return "Settings"
        case Self.studioTabID: return "Studio"
        case "visual_search": return "Visual Search"
        default: return "LuminaVault"
        }
    }

    /// HER-fix — overflow tab ids rendered outside the 5-tab TabView to
    /// avoid the system "More" overflow list.
    static let visualSearchTabId = "visual_search"

    private static func isOverflow(_ id: String) -> Bool {
        id == tabIds.settings || id == visualSearchTabId || id == studioTabID
    }

    @ViewBuilder
    private var overflowDestination: some View {
        switch selection {
        case Self.tabIds.settings:
            // HER-212: Settings — Privacy & Data + Advanced (Hermes Gateway).
            SettingsRootView()
        case Self.visualSearchTabId:
            VisualSearchView(viewModel: VisualSearchViewModel(
                ocr: ImageOCRService(),
                client: memoryClient,
                telemetry: LoggerTelemetry()
            ))
        case Self.studioTabID:
            WorkflowListView(
                client: WorkflowsHTTPClient(client: appState.makeHTTPClient()),
                memoryClient: memoryUpsertClient
            )
        default:
            EmptyView()
        }
    }

    // HER-107: tab bar split per Apple HIG — 3 primary tabs + More
    // overflow. Home / Think / Spaces are the daily-driver surfaces;
    // Settings / Visual Search live behind More.
    // HER-291: tab icons resolve via `LVIcon`; the `.tab*` cases carry
    // their `Lumina/Tab/*` branded asset paths.
    private var primaryTabItems: [LVTabItem] {
        // Order: Home · Spaces · AI · Brain · Reflect · (More trailing).
        [
            LVTabItem(id: Self.tabIds.home, label: "Home", icon: .tabHome),
            LVTabItem(id: Self.tabIds.workspaces, label: "Spaces", icon: .tabSpaces),
            LVTabItem(id: Self.tabIds.think, label: "AI", icon: .tabThink),
            // HER-235 — Brain (knowledge graph): the premium "see your
            // infra brain" surface.
            LVTabItem(id: Self.tabIds.brain, label: "Brain", icon: .brain),
            // HER-194 — Reflect: the synthesis-intelligence cluster.
            LVTabItem(id: Self.tabIds.reflect, label: "Insights", icon: .sparklesRectangleStack),
        ]
    }

    private var overflowTabItems: [LVTabItem] {
        [
            LVTabItem(id: Self.studioTabID, label: "Studio", icon: .sparklesRectangleStack),
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

    /// HER-107 — Conversations client wraps the shared BaseHTTPClient so
    /// streaming chat shares the bearer + 401 refresh coordinator.
    private var conversationsClient: any ConversationsClientProtocol {
        appState.makeConversationsClient()
    }

    /// HER-107 — non-streaming chat client (Hermes "fresh" mode).
    private var chatClient: any ChatClientProtocol {
        appState.makeChatClient()
    }

    private var chatExperienceClient: any ChatExperienceClientProtocol {
        ChatExperienceHTTPClient(client: appState.makeHTTPClient())
    }

    /// HER-107 — memory write-side client for long-press save-to-memory
    /// (distinct from read-side `memoryClient`, which only queries).
    private var memoryUpsertClient: any MemoryClientProtocol {
        MemoryHTTPClient(client: appState.makeHTTPClient())
    }

    /// HER-107 — persisted chat history (last 50 turns) keyed by
    /// conversation id. Shared actor lives in App Group container so the
    /// share extension can later seed conversations from outside the
    /// host app.
    private var chatHistoryStore: ChatHistoryStore {
        ChatHistoryStore()
    }

    private func makeChatViewModel() -> ChatViewModel {
        let settings = HybridExecutionSettingsStore()
        let executor: (any LocalChatExecuting)? = if settings.useAppleOnDeviceModel {
            makeAppleOnDeviceChatExecutor() ?? settings.configuration.map { LocalEndpointChatExecutor(configuration: $0) }
        } else {
            settings.configuration.map { LocalEndpointChatExecutor(configuration: $0) }
        }
        let cache = EncryptedLocalMemoryCache(
            fileURL: URL.applicationSupportDirectory
                .appending(path: "HybridExecution")
                .appending(path: "memories.cache"),
            keyData: KeychainService.shared.localMemoryCacheKey
        )
        let localMemorySync = LocalMemorySyncService(client: memoryUpsertClient, cache: cache)
        let viewModel = ChatViewModel(
            conversationsClient: conversationsClient,
            chatClient: chatClient,
            memoryClient: memoryUpsertClient,
            historyStore: chatHistoryStore,
            jobsClient: jobsClient,
            remindersClient: remindersClient,
            llmPreferencesClient: appState.makeLLMPreferencesClient(),
            localExecutor: executor,
            localMemorySync: localMemorySync,
            cloudAvailable: { appState.networkMonitor.isConnected }
        )
        viewModel.onOpenIntelligenceSettings = {
            selection = Self.tabIds.settings
        }
        viewModel.hybridProfile = settings.profile
        viewModel.hybridLocalFallbackEnabled = settings.localFallbackEnabled
        viewModel.hybridCloudFallbackEnabled = settings.cloudFallbackEnabled
        viewModel.syncLocalConversations = settings.syncLocalConversations
        viewModel.transport = .hybrid
        return viewModel
    }

    private var memoryGraphClient: MemoryGraphClientProtocol {
        MemoryGraphHTTPClient(client: appState.makeHTTPClient())
    }

    private var knowledgeGraphClient: KnowledgeGraphClientProtocol {
        KnowledgeGraphHTTPClient(client: appState.makeHTTPClient())
    }

    private var projectsClient: ProjectsClientProtocol {
        ProjectsHTTPClient(client: appState.makeHTTPClient())
    }

    private var jobsClient: JobsClientProtocol {
        JobsHTTPClient(client: appState.makeHTTPClient())
    }

    private var remindersClient: RemindersClientProtocol {
        RemindersHTTPClient(client: appState.makeHTTPClient())
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

    private var achievementsClient: AchievementsClientProtocol {
        AchievementsHTTPClient(client: appState.makeHTTPClient())
    }

    private var tasksClient: TasksClientProtocol {
        TasksHTTPClient(client: appState.makeHTTPClient())
    }

    private var insightsClient: InsightsClientProtocol {
        InsightsHTTPClient(client: appState.makeHTTPClient())
    }

    /// C6 — Kanban HTTP client. Follows the same makeHTTPClient() pattern as
    /// every other feature client in this file.
    private var kanbanClient: any KanbanClientProtocol {
        KanbanHTTPClient(client: appState.makeHTTPClient())
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
                    memoryClient: appState.makeMemoryClient()
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
            // PERF — destinations are lazy closures (HomeView builds them on
            // navigation). Previously every `AnyView(...)` + its view-model
            // graph allocated here on every `MainTabView.body` pass, i.e. on
            // every tab switch, even when Home wasn't visible.
            sessionsDestination: { [self] in AnyView(
                SessionsListView(vm: SessionsListViewModel(client: sessionsClient))
            ) },
            tasksDestination: { [self] in AnyView(
                TasksListView(vm: TasksListViewModel(client: tasksClient))
            ) },
            insightsDestination: { [self] in AnyView(
                InsightsListView(
                    vm: InsightsListViewModel(client: insightsClient),
                    httpClient: appState.makeHTTPClient()
                )
            ) },
            serverConnectionDestination: { [self] in AnyView(
                ServerConnectionView(vm: ServerConnectionViewModel(soulClient: soulClient))
            ) },
            skillsDestination: { [self] in AnyView(
                SkillsHubView(
                    vm: SkillsHubViewModel(client: skillsClient),
                    detailClient: skillsClient
                )
            ) },
            todayDestination: { [self] in AnyView(
                TodayView(
                    vm: TodayViewModel(client: todayClient),
                    vaultClient: vaultClient,
                    memoryClient: memoryUpsertClient
                )
            ) },
            visualSearchDestination: { [self] in AnyView(
                VisualSearchView(viewModel: VisualSearchViewModel(
                    ocr: ImageOCRService(),
                    client: memoryClient,
                    telemetry: LoggerTelemetry()
                ))
            ) },
            healthDestination: { [self] in AnyView(
                HealthDashboardScreen(
                    httpClient: appState.makeHTTPClient(),
                    coordinator: appState.healthKit
                )
            ) },
            achievementsDestination: { [self] in AnyView(
                AchievementsView(vm: AchievementsViewModel(client: achievementsClient))
            ) },
            projectsDestination: { [self] in AnyView(
                ProjectsListView(vm: ProjectsListViewModel(client: projectsClient))
            ) },
            remindersDestination: { [self] in AnyView(
                RemindersListView(vm: RemindersListViewModel(client: remindersClient))
            ) },
            jobsDestination: { [self] in AnyView(
                WorkflowListView(
                    client: WorkflowsHTTPClient(client: appState.makeHTTPClient()),
                    memoryClient: memoryUpsertClient
                )
            ) },
            // C6 — Kanban entry: loader resolves the default board then pushes KanbanBoardView.
            kanbanDestination: { [self] in AnyView(
                KanbanEntryView(client: kanbanClient)
            ) },
            // HER-56 — Deep Analytics & Patterns dashboard.
            analyticsDestination: { [self] in AnyView(
                AnalyticsDashboardScreen(httpClient: appState.makeHTTPClient())
            ) }
        )
    }

    private var skillsClient: SkillsClientProtocol {
        SkillsHTTPClient(client: appState.makeHTTPClient())
    }

    /// HER-194 — vault upload client wired so Save-to-Vault in Reflect
    /// can POST the cached rendered markdown without firing a second
    /// LLM call.
    private var vaultUploadClient: VaultUploadClientProtocol {
        VaultUploadHTTPClient(client: appState.makeHTTPClient())
    }

    private var reflect: some View {
        InsightsTabView(
            reflectViewModel: ReflectViewModel(vaultClient: vaultClient),
            runner: ReflectionRunner(
                skillsClient: skillsClient,
                vaultUploadClient: vaultUploadClient
            ),
            httpClient: appState.makeHTTPClient(),
            vaultClient: vaultClient,
            memoryClient: memoryUpsertClient
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
