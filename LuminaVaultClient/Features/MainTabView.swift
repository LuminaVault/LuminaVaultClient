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

    var body: some View {
        VStack(spacing: 0) {
            // HER-39 — pinned sync status. Hidden when idle.
            SyncStatusBanner()

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
            // Attached to the `TabView` and nowhere lower: anchors from the
            // other tabs would never reach an overlay inside a tab, and the
            // dim would stop short of the nav and tab bars. `activeTab` is
            // passed so a background tab's lingering, stale anchors are
            // dropped instead of being spotlighted.
            .guidedSpotlight(
                step: guided?.activeStep,
                activeTab: guidedTab(for: selection),
                hermieState: guided?.hermieState ?? .thinking,
                onSkip: { guided?.skip() }
            )
            // The last latch flipping is the whole point of the wizard, so
            // the celebration is hosted where nothing can clip it.
            .overlay(ConfettiOverlay(trigger: guided?.confettiTrigger ?? 0))
        }
        .environment(guided)
        .environment(\.lvReopenGuidedStart, guided.map { coordinator in
            {
                // Back to Home first: "Show me around" is meaningless on a
                // tab that does not host the card.
                selection = .home
                showSettings = false
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
