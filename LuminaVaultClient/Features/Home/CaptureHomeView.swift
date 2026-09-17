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

    @State private var vm: CaptureHomeViewModel
    @State private var glance: HomeGlanceViewModel?
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
        onOpenSettings: @escaping () -> Void
    ) {
        self._vm = State(wrappedValue: vm)
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
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if showsTodaySection {
                Section("Today") {
                    if let glance, !glance.allFailed {
                        HomeGlanceStrip(
                            memoriesToday: glance.memoriesToday,
                            streakDays: glance.streakDays,
                            toRevisit: glance.toRevisit
                        )
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
        }
        .task {
            if glance == nil { glance = makeGlanceViewModel() }
            await glance?.load()
        }
        .task { await vm.loadFeed() }
        .task { await vm.loadSpacesIfNeeded() }
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

    private var showsTodaySection: Bool {
        guard let glance else { return false }
        return !glance.allFailed || glance.recommendation != nil || failedCaptureCount > 0
    }

    @ViewBuilder
    private var recommendationRows: some View {
        switch glance?.recommendation {
        case .syncAndLearn(let count):
            HomeRecommendationRow(
                title: "Sync & Learn",
                subtitle: "^[\(count) capture](inflect: true) to learn",
                systemImage: "sparkles"
            ) {
                showingSyncAndLearn = true
            }
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
