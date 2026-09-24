// LuminaVaultClient/LuminaVaultClient/Features/MainTabView.swift
//
// The app shell: a native `TabView` with five tabs — Home, Spaces, AI, Brain,
// Insights — each owning its own `NavigationStack` and large title. The brand
// survives as the root tint and the app icon; the chrome is the system's.
//
// Settings is a sheet from Home rather than a tab, and capture is the Home
// composer rather than a floating button over the bar.
import SwiftUI

struct MainTabView: View {
    /// Tab identity. The raw values are load-bearing: `\.lvActiveTab`
    /// consumers (Rive mascots, particle fields, the Brain graph) compare
    /// them literally to decide whether to run their animation.
    enum AppTab: String, CaseIterable, Hashable {
        case home
        case workspaces
        case think
        case brain
        case reflect
    }

    @Environment(AppState.self) private var appState
    @Environment(NotificationRouter.self) private var notificationRouter
    @Environment(\.captureCoordinator) private var captureCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.lvPalette) private var palette

    @State private var selection: AppTab = .home
    /// Phase 1 — non-nil while an approval / run-completed push is being
    /// shown. `.sheet(item:)` needs an `Identifiable`, and a bare `UUID?`
    /// would re-present for the same run on every republished deep link.
    @State private var pendingHermesRunID: HermesRunPresentation?
    /// Non-nil while a workflow push is being shown. Studio is not a tab any
    /// more, and a run is a modal errand rather than a place.
    @State private var pendingWorkflow: WorkflowPresentation?
    /// A workflow push that arrived while the Settings sheet was up. Only one
    /// sheet can be presented from this view at a time, so the run waits here
    /// until Settings has finished dismissing and is presented from its
    /// `onDismiss`.
    @State private var workflowAfterSettings: WorkflowPresentation?
    @State private var showSettings = false
    @AppStorage("lv.chat.hapticsEnabled") private var hapticsEnabled = true
    @State private var tabHapticTrigger = 0
    @State private var captureFailures: CaptureFailuresStore?
    /// An ingestion push names a batch that is waiting for its files. The
    /// capture sheet opens on Files with that batch preselected.
    @State private var ingestionBatchID: UUID?
    @State private var showingIngestionCapture = false
    /// "Get started with Hermie". Created here because the shell is the only
    /// place that owns all three of its needs: the card lives on Home, the
    /// spotlight overlay must sit on the `TabView` to see every tab's
    /// anchors, and step 3 is a tab switch. Everything below reads it out of
    /// the environment.
    @State private var guided: GuidedStartCoordinator?
    /// Agent runs still working, for the banner shown on the other tabs.
    @State private var shellActivity = ShellActivity()
    @State private var showCommandPalette = false
    /// Settings chosen from the palette. Only one sheet can be up at a time,
    /// so it opens from the palette's `onDismiss`, the same hand-over the
    /// workflow push uses with Settings.
    @State private var settingsAfterPalette = false

    var body: some View {
        VStack(spacing: 0) {
            // HER-39 — pinned sync status. Hidden when idle.
            SyncStatusBanner()

            // An escalated turn keeps running after you leave the AI tab; this
            // is how you find your way back to it. Absent the rest of the time,
            // including on the AI tab, where the trail already says so.
            if shellActivity.busy, selection != .think {
                AgentWorkingBanner(count: shellActivity.runIDs.count) {
                    selection = .think
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            TabView(selection: $selection) {
                Tab("Home", systemImage: "house", value: AppTab.home) {
                    homeTab
                }

                // HER-249 — Workspaces wraps Spaces with workspace-aware
                // chrome. Underlying file/folder UI is unchanged for v1.
                Tab("Spaces", systemImage: "folder", value: AppTab.workspaces) {
                    spacesTab
                }

                // HER-107 — multi-turn chat. Memory-grounded mode streams over
                // SSE; fresh mode hits /v1/chat/completions.
                Tab("AI", systemImage: "sparkles", value: AppTab.think) {
                    aiTab
                }

                // HER-235 — the Obsidian-style knowledge graph.
                Tab("Brain", systemImage: "brain", value: AppTab.brain) {
                    brainTab
                }

                Tab("Insights", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.reflect) {
                    insightsTab
                }
            }
            .environment(\.lvActiveTab, selection.rawValue)
            .modifier(TabBarMinimizeOnScrollDown())
        }
        .lvAnimation(LVMotion.standard, value: shellActivity.busy && selection != .think)
        .environment(shellActivity)
        .background { keyboardShortcuts }
        .sheet(isPresented: $showCommandPalette, onDismiss: {
            guard settingsAfterPalette else { return }
            settingsAfterPalette = false
            showSettings = true
        }, content: {
            CommandPaletteView(entries: Self.paletteEntries) { entry in
                runPaletteEntry(entry)
            }
        })
        // Outside the `VStack`, not on the `TabView` inside it: anchors still
        // travel up from every tab, and the dim now also covers
        // `SyncStatusBanner()`, which otherwise sat undimmed and tappable
        // above a spotlight that was supposedly the only thing on screen.
        // Lower than this and the other tabs' anchors never arrive at all.
        // `activeTab` is passed so a background tab's lingering, stale
        // anchors are dropped instead of being spotlighted.
        .guidedSpotlight(
            step: guided?.activeStep,
            activeTab: guidedTab(for: selection),
            hermieState: guided?.hermieState ?? .thinking,
            onSkip: { guided?.skip() }
        )
        // The last latch flipping is the whole point of the wizard, so the
        // celebration is hosted where nothing can clip it.
        .overlay(ConfettiOverlay(trigger: guided?.confettiTrigger ?? 0))
        .environment(guided)
        .environment(\.lvReopenGuidedStart, guided.map { coordinator in
            {
                // Back to Home: "Show me around" is meaningless on a tab
                // that does not host the card. Settings closes itself.
                selection = .home
                Task { await coordinator.showMeAround() }
            }
        })
        .task {
            guard guided == nil else { return }
            let coordinator = GuidedStartCoordinator.live(appState: appState)
            guided = coordinator
            // The visibility rule renders nothing until a snapshot is in
            // hand, so the card cannot flash in and out on a cold launch.
            await coordinator.refresh()
        }
        .onChange(of: guided?.requestedTab) { _, requested in
            // Step 3 lives on the AI tab. The coordinator asks in its own
            // two-case vocabulary; mapping it to `AppTab` is the shell's job.
            guard let requested else { return }
            selection = appTab(for: requested)
        }
        .tint(palette.accent)
        .onChange(of: selection) { oldValue, newValue in
            guard oldValue != newValue, hapticsEnabled else { return }
            tabHapticTrigger += 1
        }
        .onChange(of: appState.pendingChatConversationID) { _, conversationID in
            guard conversationID != nil else { return }
            selection = .think
        }
        .onChange(of: appState.pendingChatPrefill) { _, prefill in
            guard prefill != nil else { return }
            selection = .think
        }
        .onChange(of: notificationRouter.pendingDeepLink) { _, deepLink in
            // Phase 1 — an approval or run-completed push. Presented as a
            // sheet rather than a tab switch: the run is a modal errand, and
            // a blocked approval should land on top of whatever the user was
            // doing instead of rearranging their app.
            if case .hermesRun(let runID) = deepLink {
                pendingHermesRunID = HermesRunPresentation(id: runID)
                notificationRouter.pendingDeepLink = .none
            }
            // A workflow push. This view owns the link end to end: it is
            // consumed here and the run id is handed to `WorkflowListView`,
            // which is hosted both by the sheet below and by a Settings row
            // and so cannot consume the link for itself without racing.
            if case .workflow(let runID) = deepLink {
                _ = notificationRouter.consume()
                let presentation = WorkflowPresentation(id: runID)
                if showSettings {
                    // SwiftUI presents one sheet at a time: asking for the
                    // workflow sheet now would be dropped. Close Settings and
                    // let its `onDismiss` hand over.
                    workflowAfterSettings = presentation
                    showSettings = false
                } else {
                    pendingWorkflow = presentation
                }
            }
        }
        .sheet(item: $pendingHermesRunID) { presentation in
            let runsClient = HermesRunsHTTPClient(client: appState.makeHTTPClient())
            NavigationStack {
                HermesRunDetailView(
                    vm: HermesRunDetailViewModel(client: runsClient, runID: presentation.id)
                )
            }
        }
        .sheet(item: $pendingWorkflow) { presentation in
            // Studio no longer owns a stack — it is pushed from a Settings row
            // as well as presented here — so the presenter supplies one.
            //
            // The deep link was already consumed in `onChange` above; what
            // reaches Studio is a plain run id, which it pushes on appear.
            NavigationStack {
                WorkflowListView(
                    client: WorkflowsHTTPClient(client: appState.makeHTTPClient()),
                    memoryClient: memoryUpsertClient,
                    initialRunID: presentation.id
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            // A workflow push that arrived while Settings was up closed it and
            // parked itself here; present it now that the slot is free.
            guard let presentation = workflowAfterSettings else { return }
            workflowAfterSettings = nil
            pendingWorkflow = presentation
        } content: {
            SettingsRootView()
        }
        .sensoryFeedback(.selection, trigger: tabHapticTrigger)
        .captureSheet(
            isPresented: $showingIngestionCapture,
            initialMode: .files,
            requestedBatchID: ingestionBatchID
        )
        .task(id: notificationRouter.pendingDeepLink) {
            routePendingIngestion()
            routePendingConversation()
        }
        .task(id: captureCoordinator?.queue == nil) {
            guard captureFailures == nil, captureCoordinator?.queue != nil else { return }
            let store = CaptureFailuresStore(
                queue: captureCoordinator?.queue,
                drainer: captureCoordinator?.drainerHandle ?? .noop
            )
            captureFailures = store
            await store.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            // A capture can exhaust its retries while the app is backgrounded,
            // so the count is stale by the time anyone looks at it.
            guard phase == .active else { return }
            Task { await captureFailures?.refresh() }
        }
        // The shell is the one view always on screen once signed in, so the
        // rating prompt made due by a background drain is requested here.
        .reviewPromptPresenter()
    }

    // MARK: - Keyboard

    /// Destinations the palette offers. The tab titles are the ones in the tab
    /// bar, so what you type is what you see.
    static let paletteEntries: [CommandPaletteMatcher.Entry] = [
        .init(id: "tab.home", label: "Home", group: "Tabs", keywords: ["capture", "today"]),
        .init(id: "tab.workspaces", label: "Spaces", group: "Tabs", keywords: ["files", "folders", "workspace"]),
        .init(id: "tab.think", label: "AI", group: "Tabs", keywords: ["chat", "ask", "agent"]),
        .init(id: "tab.brain", label: "Brain", group: "Tabs", keywords: ["graph", "memories"]),
        .init(id: "tab.reflect", label: "Insights", group: "Tabs", keywords: ["reflect", "analytics"]),
        .init(id: "settings", label: "Settings", group: "App", keywords: ["preferences", "theme", "account"]),
    ]

    private func runPaletteEntry(_ entry: CommandPaletteMatcher.Entry) {
        if entry.id == "settings" {
            settingsAfterPalette = true
            return
        }
        let raw = entry.id.replacingOccurrences(of: "tab.", with: "")
        if let tab = AppTab(rawValue: raw) {
            selection = tab
        }
    }

    /// Hardware-keyboard shortcuts. Invisible buttons, because a shortcut
    /// needs a control to hang on and the tab bar exposes none. Their titles
    /// are what the iPad shortcut overlay lists when Command is held.
    private var keyboardShortcuts: some View {
        Group {
            Button("Go to…") { showCommandPalette.toggle() }
                .keyboardShortcut("k", modifiers: .command)
            Button("Home") { selection = .home }.keyboardShortcut("1", modifiers: .command)
            Button("Spaces") { selection = .workspaces }.keyboardShortcut("2", modifiers: .command)
            Button("AI") { selection = .think }.keyboardShortcut("3", modifiers: .command)
            Button("Brain") { selection = .brain }.keyboardShortcut("4", modifiers: .command)
            Button("Insights") { selection = .reflect }.keyboardShortcut("5", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Guided start

    /// The guided-start vocabulary for the tab that is on screen. Tabs that
    /// host no guided target map to `nil`, which is what tells the overlay
    /// there is no anchor to look for rather than to reuse a stale one.
    private func guidedTab(for tab: AppTab) -> GuidedTab? {
        switch tab {
        case .home:  .home
        case .think: .chat
        default:     nil
        }
    }

    /// `.chat` is the AI tab, which is where the chat composer lives.
    private func appTab(for tab: GuidedTab) -> AppTab {
        switch tab {
        case .home: .home
        case .chat: .think
        }
    }

    /// An ingestion push carries the batch the user just started elsewhere
    /// (Hermes, the web app) and needs files for. Home owns it because the
    /// capture sheet is a Home affordance; the push is consumed here so no
    /// other surface re-presents it.
    private func routePendingIngestion() {
        guard case let .ingestion(batchID, _) = notificationRouter.pendingDeepLink else { return }
        selection = .home
        ingestionBatchID = batchID
        showingIngestionCapture = true
        _ = notificationRouter.consume()
    }

    /// Muse Stage D — a tapped proactive-chat push, a `luminavault://chat/`
    /// URL or a tap on the agent-run Live Activity. Hands the thread to the
    /// same `AppState.openChat(conversationID:)` path the inbox uses, which
    /// switches to the AI tab and pushes the conversation.
    ///
    /// Runs from `.task(id:)` rather than `onChange` so a link parked before
    /// this view existed (cold start, or a tap while signed out) is routed
    /// the moment the tab view appears, not only on the next change.
    private func routePendingConversation() {
        guard case let .conversation(id) = notificationRouter.pendingDeepLink else { return }
        _ = notificationRouter.consume()
        // A sheet would sit on top of the thread and hide it.
        showSettings = false
        appState.openChat(conversationID: id)
    }

    // MARK: - Tabs

    /// The Home tab. Wrapped in a `NavigationStack` so a feed row can push
    /// the reader, matching how the vault's own list behaves.
    private var homeTab: some View {
        NavigationStack {
            CaptureHomeView(
                vm: CaptureHomeViewModel(
                    // Both nil until the vault is prepared; the composer
                    // disables saving in that window rather than accepting a
                    // capture it cannot store.
                    queue: captureCoordinator?.queue,
                    drainer: captureCoordinator?.drainerHandle ?? .noop,
                    vaultClient: vaultClient,
                    spacesClient: captureCoordinator?.spacesClient
                ),
                vaultClient: vaultClient,
                // The reader edits notes, so it needs the upsert face of the
                // memory API rather than the query one.
                memoryClient: memoryUpsertClient,
                captureFailures: captureFailures,
                onOpenSettings: { showSettings = true }
            )
        }
    }

    private var spacesTab: some View {
        NavigationStack {
            WorkspacesView(
                vm: SpacesViewModel(spacesClient: spacesClient),
                vaultClient: vaultClient,
                memoryClient: memoryClient,
                memoryDetailClient: memoryUpsertClient,
                uploadClient: vaultUploadClient,
                teamClient: TeamHTTPClient(client: appState.makeHTTPClient()),
                activeVaultStore: appState.activeVaultStore,
                currentUserIDProvider: { appState.currentUserId }
            )
        }
    }

    /// `ThinkWithLuminaView` owns its own `NavigationStack`.
    private var aiTab: some View {
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
    }

    /// `BrainTabView` owns its own `NavigationStack`, and its own capture
    /// toolbar item with it — a `.toolbar` declared out here would have no
    /// bar to attach to.
    private var brainTab: some View {
        BrainTabView(
            client: memoryGraphClient,
            knowledgeClient: knowledgeGraphClient,
            memoryClient: memoryUpsertClient
        )
    }

    private var insightsTab: some View {
        let httpClient = appState.makeHTTPClient()
        return NavigationStack {
            InsightsTabView(
                analyticsViewModel: AnalyticsDashboardViewModel(
                    analytics: AnalyticsHTTPClient(client: httpClient),
                    insights: InsightsHTTPClient(client: httpClient)
                ),
                reflectViewModel: ReflectViewModel(vaultClient: vaultClient),
                runner: ReflectionRunner(
                    skillsClient: skillsClient,
                    vaultUploadClient: vaultUploadClient
                ),
                httpClient: httpClient,
                vaultClient: vaultClient,
                memoryClient: memoryUpsertClient
            )
            .captureToolbarItem()
        }
    }

    // MARK: - Clients

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
            // Lets chat follow a turn that escalates to an agent run. Same
            // client the Agent Runs screen uses.
            runsClient: HermesRunsHTTPClient(client: appState.makeHTTPClient()),
            telemetry: AnalyticsTelemetry(),
            cloudAvailable: { appState.networkMonitor.isConnected }
        )
        viewModel.onOpenIntelligenceSettings = {
            showSettings = true
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

    private var jobsClient: JobsClientProtocol {
        JobsHTTPClient(client: appState.makeHTTPClient())
    }

    private var remindersClient: RemindersClientProtocol {
        RemindersHTTPClient(client: appState.makeHTTPClient())
    }

    private var memoClient: MemoClientProtocol {
        MemoHTTPClient(client: appState.makeHTTPClient())
    }

    private var suggestionsClient: SuggestionsClientProtocol {
        SuggestionsHTTPClient(client: appState.makeHTTPClient())
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
}

/// `.sheet(item:)` fodder for a workflow run arriving by push.
private struct WorkflowPresentation: Identifiable, Equatable {
    let id: UUID
}

/// The bar collapses as you scroll down on iOS 26; earlier releases keep it
/// fixed, which is their own native behaviour.
private struct TabBarMinimizeOnScrollDown: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}
