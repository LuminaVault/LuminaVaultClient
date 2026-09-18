// LuminaVaultClient/LuminaVaultClient/Features/Home/CaptureHomeView.swift
//
// Home is capture.
//
// One composer at the top, three numbers and at most one suggestion under it,
// then what you have recently saved. The dashboard this tab used to open on is
// gone: the first thing a new user saw was a report about a vault they had not
// filled yet, and the vault is the product.

import SwiftUI
import LuminaVaultShared

struct CaptureHomeView: View {
    @Environment(AppState.self) private var appState
    /// "Get started with Hermie". Created by `MainTabView`; optional so a
    /// preview or a snapshot suite that does not stand up the shell simply
    /// renders Home without the card.
    @Environment(GuidedStartCoordinator.self) private var guided: GuidedStartCoordinator?

    @State private var vm: CaptureHomeViewModel
    @State private var glance: HomeGlanceViewModel?
    @State private var ticker: NewsTickerViewModel?
    @FocusState private var composerFocused: Bool
    @State private var sheetPresented = false
    @State private var sheetMode: CaptureSheet.Mode = .photo
    @State private var showingSyncAndLearn = false
    @State private var showingCaptureReview = false

    private let vaultClient: VaultClientProtocol
    private let memoryClient: MemoryClientProtocol
    /// Captures that gave up retrying. Nil until the capture queue exists.
    private let captureFailures: CaptureFailuresStore?
    /// Opens Settings, which is a sheet from here rather than a tab.
    private let onOpenSettings: () -> Void

    init(
        vm: CaptureHomeViewModel,
        vaultClient: VaultClientProtocol,
        memoryClient: MemoryClientProtocol,
        captureFailures: CaptureFailuresStore? = nil,
        // The glance view model is normally built here from `AppState`, which
        // a preview or a snapshot test has no live clients for.
        glance: HomeGlanceViewModel? = nil,
        // Same story for the breaking-news strip.
        ticker: NewsTickerViewModel? = nil,
        onOpenSettings: @escaping () -> Void
    ) {
        self._vm = State(wrappedValue: vm)
        self._glance = State(wrappedValue: glance)
        self._ticker = State(wrappedValue: ticker)
        self.vaultClient = vaultClient
        self.memoryClient = memoryClient
        self.captureFailures = captureFailures
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        List {
            Section {
                HomeComposer(
                    text: $vm.text,
                    focused: $composerFocused,
                    isSaving: vm.saving,
                    detectedLink: vm.detectedLink,
                    canSave: vm.canSave,
                    isRecording: vm.isRecording,
                    recordingElapsed: vm.recorder.elapsed,
                    spaces: vm.availableSpaces ?? [],
                    selectedSpaceID: $vm.selectedSpaceID,
                    onSubmit: { Task { await vm.submit() } },
                    onVoice: { Task { await vm.toggleRecording() } },
                    onCancelRecording: { vm.cancelRecording() },
                    onPhotos: { present(.photo) },
                    onFiles: { present(.files) }
                )
                // Step 1's spotlight. The mark goes on the composer itself,
                // not the row, so the hole is the control being taught.
                .guidedTarget(.composer, in: .home)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if showsTodaySection {
                Section("Today") {
                    // The get-started card owns the top of Home until it is
                    // finished. It brings its own card surface, so it rides a
                    // clear row like the composer does.
                    if isGuidedCardVisible, let guided {
                        GuidedStartCard(
                            progress: guided.progress,
                            hermieState: guided.hermieState,
                            message: guided.inlineMessage,
                            onSelect: { step in Task { await guided.start(step) } },
                            onDismiss: { Task { await guided.dismissCard() } }
                        )
                        .onAppear { guided.noteCardShown() }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                    // `glance` is nil until `.task` builds it, which is after
                    // the first paint. Drawing the strip's own loading state
                    // holds the row's height from frame one instead of
                    // letting the section pop in under the composer.
                    if let glance {
                        if !glance.allFailed {
                            HomeGlanceStrip(
                                memoriesToday: glance.memoriesToday,
                                streakDays: glance.streakDays,
                                toRevisit: glance.toRevisit
                            )
                        }
                    } else {
                        HomeGlanceStrip(
                            memoriesToday: .loading,
                            streakDays: .loading,
                            toRevisit: .loading
                        )
                    }
                    // The breaking-news strip of the first-party news-ticker
                    // plugin. Hides itself when the plugin is not installed —
                    // and stays hidden while the get-started card is up, so a
                    // first-time user sees exactly one thing to do. It comes
                    // back once the card is completed or dismissed.
                    if let ticker, !isGuidedCardVisible {
                        HomeNewsTickerStrip(viewModel: ticker)
                    }
                    recommendationRows
                }
            }

            Section("Recent") {
                RecentSavesFeed(
                    pending: vm.visiblePending,
                    files: vm.files.displayedFiles,
                    vaultClient: vaultClient,
                    memoryClient: memoryClient,
                    isLoading: vm.files.isLoading,
                    hasMore: vm.files.nextCursor != nil,
                    spaceName: { vm.spaceName(for: $0) },
                    onLoadMore: { Task { await vm.files.loadMore() } },
                    onRetry: { row in Task { await vm.retry(row) } },
                    onDiscard: { row in Task { await vm.discard(row) } }
                )
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "person.crop.circle", action: onOpenSettings)
            }
        }
        .safeAreaInset(edge: .top) {
            if let toast = vm.toast {
                statusBanner(toast)
            }
        }
        .refreshable {
            await vm.loadFeed()
            await glance?.load()
            await ticker?.refresh()
        }
        .task {
            if glance == nil { glance = makeGlanceViewModel() }
            if ticker == nil { ticker = makeTickerViewModel() }
            await glance?.load()
        }
        .task { await vm.loadFeed() }
        .task { await vm.loadSpacesIfNeeded() }
        // The glance is loaded once on appear and on pull-to-refresh, so by
        // the time a step opens its counts are older than the capture that
        // got the user here. Re-reading it when the active step changes is
        // what makes the row say "1 capture to learn" instead of nothing.
        // The row itself no longer depends on this landing — see
        // `showsGuidedSyncRow` — but the number does.
        .task(id: guided?.activeStep) {
            guard guided?.activeStep != nil else { return }
            await glance?.load()
        }
        // A nudge, not a completion: the server owns the latch. A capture
        // leaving the pending list means the drainer got it uploaded, which
        // is the earliest moment `firstCaptureCompleted` can possibly be
        // true — so poll now instead of waiting out the backoff. Lives here,
        // as a view-level `onChange`, so `CaptureHomeViewModel` stays unaware
        // that a wizard exists.
        .onChange(of: vm.visiblePending.count) { previous, current in
            guard previous > 0, current == 0 else { return }
            guided?.noteUserAction(.saveMemory)
        }
        .captureSheet(isPresented: $sheetPresented, initialMode: sheetMode)
        .sheet(isPresented: $showingSyncAndLearn) {
            NavigationStack {
                SyncAndLearnView(
                    vm: SyncAndLearnViewModel(
                        repository: appState.vaultRepository,
                        pendingClient: appState.makeKBCompileClient(),
                        webSocket: appState.makeKBCompileWebSocketClient(),
                        memoryClient: appState.makeMemoryClient()
                    )
                )
            }
        }
        .sheet(isPresented: $showingCaptureReview) {
            if let captureFailures {
                CaptureReviewSheet(store: captureFailures)
            }
        }
    }

    // MARK: - Today

    private var failedCaptureCount: Int { captureFailures?.count ?? 0 }

    /// The one predicate the contract asks for: the card's own visibility
    /// rule, read once and used both to place the card and to hold the
    /// breaking-news strip back.
    private var isGuidedCardVisible: Bool { guided?.isCardVisible ?? false }

    /// Nil is loading, not empty: the section stays for the redacted strip
    /// and only disappears once the calls have come back with nothing.
    ///
    /// The card is reason enough on its own — a brand-new account is exactly
    /// where the glance calls are most likely to come back empty or failed,
    /// and that is precisely when the card must be on screen.
    private var showsTodaySection: Bool {
        if isGuidedCardVisible { return true }
        guard let glance else { return true }
        return !glance.allFailed || glance.recommendation != nil || failedCaptureCount > 0
    }

    /// True when step 2 is open and the glance heuristic is not already
    /// rendering the row its spotlight points at.
    ///
    /// The heuristic is stale by construction here: `glance.load()` runs on
    /// first appear and on pull-to-refresh, never after a capture — so on the
    /// canonical path (save a memory, step 2 opens) it still holds the
    /// pre-save zero while the wizard's own live probe correctly says there
    /// is something to compile. Leaving the anchor to it means step 2 opens
    /// on a row that is not there.
    ///
    /// "Is there anything to compile?" and "is this worth recommending right
    /// now?" are different questions. The step asks the first one directly.
    private var showsGuidedSyncRow: Bool {
        guard guided?.activeStep == .syncLearn else { return false }
        if case .syncAndLearn = glance?.recommendation { return false }
        return true
    }

    /// The row step 2 teaches. `count` is nil when the glance has not caught
    /// up — the row still works, it just does not claim a number it does not
    /// have.
    private func syncAndLearnRow(count: Int?) -> some View {
        HomeRecommendationRow(
            title: "Sync & Learn",
            subtitle: count.map { "^[\($0) capture](inflect: true) to learn" },
            systemImage: "sparkles"
        ) {
            showingSyncAndLearn = true
        }
        // Step 2's spotlight.
        .guidedTarget(.sync, in: .home)
    }

    @ViewBuilder
    private var recommendationRows: some View {
        if showsGuidedSyncRow {
            syncAndLearnRow(count: nil)
        }

        switch glance?.recommendation {
        case .syncAndLearn(let count):
            syncAndLearnRow(count: count)
        case .dailyReview(let count):
            NavigationLink {
                DailyReviewView(
                    vm: DailyReviewViewModel(client: appState.makeDailyReviewClient())
                )
            } label: {
                HomeRecommendationLabel(
                    title: "Daily review",
                    subtitle: "^[\(count) memory](inflect: true) to revisit",
                    systemImage: "sun.max"
                )
            }
        case .none:
            EmptyView()
        }

        if failedCaptureCount > 0 {
            HomeRecommendationRow(
                title: "^[\(failedCaptureCount) capture](inflect: true) need attention",
                systemImage: "exclamationmark.triangle.fill"
            ) {
                showingCaptureReview = true
            }
        }
    }

    private func makeTickerViewModel() -> NewsTickerViewModel {
        NewsTickerViewModel(
            client: NewsTickerHTTPClient(client: appState.makeHTTPClient()),
            store: NewsTickerLocalStore(container: appState.modelContainer)
        )
    }

    private func makeGlanceViewModel() -> HomeGlanceViewModel {
        HomeGlanceViewModel(
            homeClient: HomeSummaryHTTPClient(client: appState.makeHTTPClient()),
            dailyReviewClient: appState.makeDailyReviewClient(),
            pendingClient: appState.makeKBCompileClient()
        )
    }

    // MARK: - Toast

    @ViewBuilder
    private func statusBanner(_ toast: CapturePhotosViewModel.ToastKind) -> some View {
        let failed: Bool = if case .failed = toast { true } else { false }
        HStack(spacing: 8) {
            Image(systemName: failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(failed ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
            Text(Self.message(for: toast))
                .font(.footnote)
            Spacer(minLength: 0)
            Button("Dismiss") { vm.toast = nil }
                .font(.footnote)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .accessibilityElement(children: .combine)
        // A success clears itself; a failure stays until it is read, because it
        // is the only sign the capture did not happen.
        .task(id: Self.message(for: toast)) {
            guard !failed else { return }
            try? await Task.sleep(for: .seconds(3))
            vm.toast = nil
        }
    }

    private static func message(for toast: CapturePhotosViewModel.ToastKind) -> String {
        switch toast {
        case let .savedOnline(count): return count == 1 ? "Saved." : "Saved \(count) items."
        case .queuedOffline: return "Saved to your vault."
        case let .failed(reason): return reason
        }
    }

    /// Photos and files already work well in the capture sheet — offline
    /// queued, with a Space picker. One tap from the composer is not a worse
    /// product than an inline picker; a second implementation of one is worse
    /// code.
    private func present(_ mode: CaptureSheet.Mode) {
        composerFocused = false
        sheetMode = mode
        sheetPresented = true
    }
}
