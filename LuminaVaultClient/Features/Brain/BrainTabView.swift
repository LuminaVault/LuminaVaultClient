// The Brain tab: one graph of notes and memories across every vault. This view
// wires the store (when to ask the server), the model (what is visible), the
// selection, the renderer (the 2D canvas, or the Constellation once picked),
// the selection tray, the detail sheet and the reasoning sheet, and owns no
// rules of its own: which card shows, the badge, the status line, the request
// and the 2D / Constellation switch come from `BrainTabState`; what the tray
// offers comes from `BrainTrayActions`.
//
// Derivation order on every change: build `visible` → `selection.prune` →
// renderer data (colours) → renderer highlight. The first two run in
// `rederive()`; the last two are read in `body` from what it left.

import LuminaVaultShared
import SwiftUI

struct BrainTabView: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.captureCoordinator) private var captureCoordinator
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The shell's tab selection: the active vault is read again when it changes.
    @Environment(\.lvActiveTab) private var activeTab

    @State private var store: BrainGraphStore
    @State private var selection = BrainSelection()
    @State private var filters: BrainGraphFilters
    /// The point the graph is focused on, and how many steps out. View state,
    /// set by the tray or a deep link.
    @State private var focus: String?
    @State private var depth = 1
    @State private var similarAsked: Bool
    /// The focus whose point has been selected once already.
    @State private var focusSelectedFor: String?

    // Derived by `rederive()`.
    @State private var visible: VisibleBrainGraph?
    @State private var legend: (keys: [BrainLegendKey], more: Int) = ([], 0)
    /// What the renderer on screen draws, built only when the graph, the
    /// colours, the theme or the view change (`rebuildScene`), never on a
    /// search keystroke or a selection.
    @State private var canvasScene: BrainCanvasScene?
    @State private var skyModel: ConstellationModel?
    /// The selection tray's last measured height. The tray is overlaid, so
    /// selecting never resizes the renderer; this only centres a searched
    /// point above it. Kept when the tray goes, for the next search.
    @State private var trayHeight = BrainTabState.trayHeightEstimate

    @State private var searchText = ""
    @State private var searchPresented = false
    @State private var centre: BrainCentreRequest?
    @State private var showFilters = false
    @State private var showList = false
    @State private var showCapture = false

    // Tray, detail and reasoning.
    @State private var detail: BrainNodeDetail
    @State private var reasoning: KnowledgeReasoningViewModel?
    @State private var showReasoning = false
    /// What to present once the reasoning sheet has gone.
    @State private var afterReasoning: (() -> Void)?
    /// Read when the tab appears and each time the tab changes; the reasoning
    /// routes are scoped to it.
    @State private var activeVaultID: UUID?
    @State private var activeVaultTracker = BrainActiveVaultTracker()
    /// The entry request last applied (or seeded into the first focus).
    @State private var appliedEntry: Int?

    /// The stored 2D / Constellation choice; nil until one is picked (2D).
    @State private var savedView: BrainViewChoice?
    private let prefsDefaults: UserDefaults?
    private let memoryClient: (any MemoryClientProtocol)?
    private let activeVault: @Sendable () async -> UUID?
    /// The shell's latest request; cleared once applied.
    @Binding private var entry: BrainEntryRequest?

    /// `memoryClient` loads a memory for Open; `knowledgeClient` answers the
    /// reasoning sheet (Explain and Ask are disabled without it);
    /// `activeVault` names the vault those answers come from.
    init(
        client: any BrainGraphClientProtocol,
        memoryClient: (any MemoryClientProtocol)? = nil,
        knowledgeClient: (any KnowledgeGraphClientProtocol)? = nil,
        activeVault: @escaping @Sendable () async -> UUID? = { nil },
        focus: String? = nil,
        entry: Binding<BrainEntryRequest?> = .constant(nil),
        prefs: UserDefaults? = .standard
    ) {
        // A request that made this tab is part of its first request, not a
        // second one after it.
        let first = BrainEntryRequest.apply(entry.wrappedValue, lastApplied: nil)
        let stored = BrainPrefs.load(from: prefs)
        _store = State(initialValue: BrainGraphStore(client: client))
        _detail = State(initialValue: BrainNodeDetail(client: memoryClient))
        _reasoning = State(initialValue: knowledgeClient.map { KnowledgeReasoningViewModel(client: $0) })
        self.memoryClient = memoryClient
        self.activeVault = activeVault
        var startFilters = stored.filters
        if let first { startFilters.vaults = first.vaults(keeping: startFilters.vaults) }
        _filters = State(initialValue: startFilters)
        _similarAsked = State(initialValue: BrainTabState.similarAsked(previously: false, filters: startFilters))
        _focus = State(initialValue: first.map(\.focus) ?? focus)
        _appliedEntry = State(initialValue: first?.token)
        _entry = entry
        _savedView = State(initialValue: stored.view)
        prefsDefaults = prefs
    }

    private var request: BrainGraphRequest {
        BrainTabState.request(
            vaults: filters.vaults, known: store.knownVaults.map(\.id),
            focus: focus, depth: depth, similarAsked: similarAsked
        )
    }

    private var card: BrainTabCard {
        BrainTabState.card(state: store.state, request: store.request, visible: visible)
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.backgroundBase)
                .navigationTitle("Brain")
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .top, spacing: 0) { statusBar }
                .toolbar { toolbar }
                // Declared inside the stack: a `.toolbar` on the view that
                // contains a `NavigationStack` has no bar to attach to.
                .captureToolbarItem()
                .searchable(text: $searchText, isPresented: $searchPresented, prompt: BrainTabState.searchPrompt)
                .searchSuggestions { searchSuggestions }
                .task(id: request) { store.sync(request) }
                .task(id: activeTab) { await readActiveVault() }
                .onChange(of: entry, initial: true) { applyEntry() }
                .onChange(of: derivationKey, initial: true) { rederive() }
                .onChange(of: filters) { _, next in
                    similarAsked = BrainTabState.similarAsked(previously: similarAsked, filters: next)
                    BrainPrefs(filters: next, view: savedView).save(to: prefsDefaults)
                    rederive()
                }
                .onChange(of: focus) { _, next in
                    if next == nil {
                        depth = 1
                        focusSelectedFor = nil
                    }
                }
                .sheet(isPresented: $showFilters) {
                    filterSheet
                        // A medium form sheet on an iPad shows two rows.
                        .presentationDetents(sizeClass == .regular ? [.large] : [.medium, .large])
                }
                .fullScreenCover(isPresented: $showList) { listSheet }
                .captureSheet(isPresented: $showCapture, initialMode: .photo)
                .sheet(isPresented: $detail.isOpen) { detailSheet }
                .sheet(isPresented: $showReasoning, onDismiss: presentAfterReasoning, content: { reasoningSheet })
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch card {
        case .firstLoad:
            VStack(spacing: LVSpacing.base) {
                ProgressView().controlSize(.large)
                Text(BrainTabState.firstLoadText)
                    .font(.callout)
                    .foregroundStyle(palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
        case .graph:
            if let visible {
                canvas(visible)
                    // Over the renderer, not a safe-area inset: the renderer
                    // keeps its size when the tray comes and goes, so
                    // selecting never refits or recentres the camera.
                    .overlay(alignment: .bottom) { tray(visible) }
                #if DEBUG
                    .overlayPreferenceValue(BrainUITestProbeKey.self) { BrainUITestProbeMark(point: $0) }
                #endif
            }
        case .empty:
            emptyCard
        case let .failed(message, showAllVaults):
            failedCard(message, showAllVaults: showAllVaults)
        case .missingFocus:
            messageCard(BrainTabState.missingFocusText) {
                Button(BrainTabState.showFullGraphTitle) { focus = nil }
                    .buttonStyle(.lvProminent)
            }
        case .nothingMatches:
            messageCard(BrainTabState.nothingMatchesText) {
                Button(BrainTabState.resetTitle, action: resetFilters)
                    .buttonStyle(.lvProminent)
            }
        }
    }

    /// The renderer on screen: only one exists at a time, so the
    /// Constellation's scene is made only once it is picked.
    @ViewBuilder
    private func canvas(_ visible: VisibleBrainGraph) -> some View {
        let theme = BrainGraphTheme(palette: palette, scheme: scheme)
        let by = filters.colourBy
        let order = colourOrder
        let index = visible.index
        let colourOf: (BrainGraphNodeDTO) -> Color = { node in
            theme.categoryColour(for: BrainGraphModel.colourKey(node, by: by, index: index), order: order)
        }
        let summary = BrainTabState.selectionSummary(selection.selected, index: index)
        switch shownView {
        case .twoD:
            BrainGraphCanvas(
                graph: visible,
                highlight: highlight(index),
                colourOf: colourOf,
                onTap: { id, additive in selection.click(id, additive: additive) },
                onBackgroundTap: { selection.clear() },
                // A double tap opens a point, as the tray's Open does.
                onOpen: { id in open(id, index: index) },
                centreOn: centre,
                bottomInset: trayHeight,
                scene: canvasScene
            )
            .accessibilityIdentifier("brain.canvas")
            .accessibilityValue(summary)
        case .threeD:
            BrainGraphRealityView(
                graph: visible,
                highlight: highlight(index),
                colourOf: colourOf,
                onTap: { id, additive in selection.click(id, additive: additive) },
                onBackgroundTap: { selection.clear() },
                onOpen: { id in open(id, index: index) },
                centreOn: centre,
                covered: BrainTabState.isCovered(
                    filters: showFilters, list: showList, capture: showCapture,
                    detail: detail.isOpen, reasoning: showReasoning
                )
            )
            .accessibilityIdentifier("brain.constellation")
            .accessibilityValue(summary)
        }
    }

    private var shownView: BrainViewChoice {
        BrainPrefs(filters: filters, view: savedView).effectiveView(explicit: nil)
    }

    /// The overflow menu's 2D / Constellation choice. Never asks for a graph
    /// and keeps the selection.
    private func show(_ next: BrainViewChoice) {
        guard let change = BrainTabState.switchView(shown: shownView, to: next, filters: filters) else { return }
        savedView = next
        change.prefs.save(to: prefsDefaults)
        AccessibilityNotification.Announcement(change.note).post()
    }

    private var emptyCard: some View {
        ScrollView {
            VStack(spacing: LVSpacing.base) {
                LVEmptyState(
                    mascot: .thinking,
                    headline: BrainTabState.emptyHeadline,
                    supporting: BrainTabState.emptySupporting
                ),
                bottomInset: trayHeight,
                model: skyModel
                Button(BrainTabState.captureTitle, systemImage: "plus") { showCapture = true }
                    .buttonStyle(.lvProminent)
                    .controlSize(.large)
                    .disabled(captureCoordinator?.queue == nil || captureCoordinator?.ingestionClient == nil)
                    .accessibilityIdentifier("brain.empty.capture")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LVSpacing.xl)
        }
        .defaultScrollAnchor(.center)
    }

    private func failedCard(_ message: String, showAllVaults: Bool) -> some View {
        messageCard(message, icon: "exclamationmark.triangle") {
            Button(BrainTabState.retryTitle) { store.retry() }
                .buttonStyle(.lvProminent)
                .accessibilityIdentifier("brain.failed.retry")
            if showAllVaults {
                Button(BrainTabState.showAllVaultsTitle) { filters.vaults = nil }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func messageCard(
        _ text: String, icon: String? = nil, @ViewBuilder actions: () -> some View
    ) -> some View {
        ScrollView {
            VStack(spacing: LVSpacing.base) {
                if let icon {
                    Image(systemName: icon)
                        .font(.largeTitle)
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityHidden(true)
                }
                Text(text)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.textPrimary)
                actions()
                    .controlSize(.large)
            }
            .padding(LVSpacing.xl)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
    }

    // MARK: Bar

    @ViewBuilder
    private var statusBar: some View {
        if let line = BrainTabState.statusLine(
            card: card,
            visible: visible,
            facts: BrainRefreshFacts(
                truncated: store.truncatedCount != nil,
                stale: store.stale,
                rateLimited: store.rateLimited,
                refreshError: store.refreshError,
                refreshing: store.refreshing
            )
        ) {
            BrainStatusBar(line: line, refreshing: store.refreshing, retry: { store.retry() })
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if focus != nil {
            ToolbarItem(placement: .topBarLeading) {
                Button(BrainTabState.fullGraphTitle) { focus = nil }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            BrainFiltersButton(changed: BrainTabState.badgeCount(filters)) { present { showFilters = true } }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker(BrainTabState.viewMenuTitle, selection: Binding(get: { shownView }, set: { show($0) })) {
                    Label(BrainTabState.twoDTitle, systemImage: "circle.grid.cross")
                        .tag(BrainViewChoice.twoD)
                    Label(BrainTabState.constellationTitle, systemImage: "sparkles")
                        .tag(BrainViewChoice.threeD)
                }
                .pickerStyle(.inline)
                Button("List", systemImage: "list.bullet") { present { showList = true } }
                Button("Reload", systemImage: "arrow.clockwise") { store.retry() }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .accessibilityIdentifier("brain.more")
        }
    }

    // MARK: Entry and vault

    /// A new entry request replaces the focus (or clears it for the full graph)
    /// at the default depth. The focus point is selected again once it loads.
    private func applyEntry() {
        defer { entry = BrainEntryRequest.acknowledge(entry, applied: appliedEntry) }
        guard let applied = BrainEntryRequest.apply(entry, lastApplied: appliedEntry) else { return }
        appliedEntry = applied.token
        // Nothing will load when the request does not change: select now.
        let changes = applied.changesRequest(
            focus: focus, depth: depth, vaults: filters.vaults,
            known: store.knownVaults.map(\.id), similarAsked: similarAsked
        )
        depth = applied.depth
        focusSelectedFor = nil
        focus = applied.focus
        filters.vaults = applied.vaults(keeping: filters.vaults)
        if !changes { rederive() }
    }

    /// The vault the reasoning sheet speaks for. Another tab can change it, so
    /// it is read again on return; an answer about the old one goes, the
    /// selection and the graph stay, and no graph is asked for.
    private func readActiveVault() async {
        let id = await activeVault()
        if activeVaultTracker.observe(id) { reasoning?.discardAnswer() }
        activeVaultID = id
    }

    // MARK: Search

    @ViewBuilder
    private var searchSuggestions: some View {
        if let visible {
            ForEach(BrainGraphModel.search(visible.nodes, query: searchText), id: \.id) { node in
                Button { pick(node.id) } label: {
                    Label(node.label, systemImage: BrainTabState.isItem(node) ? "doc.text" : "circle.circle")
                }
                .accessibilityIdentifier("brain.search.\(node.label)")
            }
        }
    }

    /// Selects the point and centres the view on it: search's one camera move.
    private func pick(_ id: String) {
        selection.selectGroup([id], additive: false)
        centre = BrainCentreRequest(id: id, token: (centre?.token ?? 0) + 1)
        searchText = ""
        searchPresented = false
    }

    // MARK: Tray

    /// In the order picked; a point a filter hides drops out at once.
    private func selectedNodes(_ index: BrainGraphIndex) -> [BrainGraphNodeDTO] {
        selection.selected.compactMap { index.byID[$0] }
    }

    /// The selection's highlight, plus the memories a reasoning answer names
    /// while the reasoning sheet is open.
    private func highlight(_ index: BrainGraphIndex) -> BrainHighlight {
        let base = selection.highlight(index: index)
        guard showReasoning, let reasoning else { return base }
        return BrainTrayActions.withReasoning(
            base, memoryIDs: reasoning.highlightedMemoryIDs.map(\.uuidString), index: index
        )
    }

    @ViewBuilder
    private func tray(_ visible: VisibleBrainGraph) -> some View {
        let nodes = selectedNodes(visible.index)
        if !nodes.isEmpty {
            BrainSelectionTray(
                nodes: nodes,
                actions: BrainTrayActions.actions(
                    for: nodes, index: visible.index, reasoningAvailable: reasoning != nil
                ),
                onRemove: { selection.remove($0) },
                onClear: { selection.clear() },
                onAction: { runTray($0, nodes: nodes, index: visible.index) }
            )
        }
    }

    /// Nothing in a tray action asks for the graph except Focus.
    private func runTray(_ id: BrainTrayActionID, nodes: [BrainGraphNodeDTO], index: BrainGraphIndex) {
        guard let outcome = BrainTrayActions.run(
            id, nodes: nodes, index: index, activeVault: activeVaultID, reasoningAvailable: reasoning != nil
        ) else { return }
        switch outcome {
        case let .select(ids):
            selection.selectGroup(ids, additive: false)
        case let .focus(id):
            depth = 1
            focus = id
        case let .open(node):
            present { detail.show(node) }
        case let .explain(from, to):
            guard let reasoning else { return }
            // A fresh question: the answer to an earlier one no longer applies.
            reasoning.result = nil
            showReasoning = true
            reasoning.explainNodes(from: from, to: to, subject: BrainTrayActions.explainSubject(nodes))
        case let .ask(query, send):
            guard let reasoning else { return }
            reasoning.prefill(query)
            showReasoning = true
            if send { reasoning.reason() }
        }
    }

    /// A double tap: selects the point if it is not already, then runs the
    /// tray's Open on it alone (a group is selected, not opened).
    private func open(_ id: String, index: BrainGraphIndex) {
        guard let node = index.byID[id] else { return }
        if !selection.selected.contains(id) { selection.selectGroup([id], additive: false) }
        if case let .open(point)? = BrainTrayActions.run(.open, nodes: [node], index: index, activeVault: activeVaultID) {
            present { detail.show(point) }
        }
    }

    /// Runs what `present` queued once the reasoning sheet has gone.
    private func presentAfterReasoning() {
        let next = afterReasoning
        afterReasoning = nil
        next?()
    }

    /// One sheet at a time: the reasoning sheet leaves the graph usable
    /// behind it, so it closes (keeping its answer) before another opens,
    /// as the web's reasoning and filter panels never share the screen.
    private func present(_ show: @escaping () -> Void) {
        guard showReasoning else { return show() }
        // Runs from the sheet's onDismiss: the next sheet cannot present
        // until the dismissal has landed.
        afterReasoning = show
        showReasoning = false
    }

    // MARK: Sheets

    private var detailSheet: some View {
        let node = detail.node
            // An overlay offers the whole height, and the chips' horizontal
            // scroll view would take it: the tray keeps its own height.
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                if height > 0 { trayHeight = height }
            }
        return BrainNodeDetailSheet(
            detail: detail,
            vaultName: vaultName(node?.vaultID),
            spaceName: node?.spaceID.flatMap { BrainTabState.spaceName($0, in: loadedGraph) },
            activeVaultID: activeVaultID
        )
    }

    @ViewBuilder
    private var reasoningSheet: some View {
        if let reasoning {
            KnowledgeReasoningSheet(
                viewModel: reasoning,
                vaultName: vaultName(activeVaultID),
                memoryClient: memoryClient
            )
        }
    }

    private func vaultName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return store.knownVaults.first { $0.id == id }?.name
    }

    private var filterSheet: some View {
        BrainFilterSheet(
            filters: $filters,
            depth: $depth,
            focus: focus,
            knownVaults: store.knownVaults,
            legend: legend,
            noSimilarFound: BrainGraphModel.noSimilarFound(
                loadedGraph, loaded: store.loaded, similarOn: filters.links[.similar] ?? false
            ),
            onReset: resetFilters
        )
    }

    private var listSheet: some View {
        BrainListView(
            visible: visible,
            vaults: store.knownVaults,
            selection: selection
        )
    }

    private func resetFilters() {
        filters = BrainGraphModel.defaultFilters()
    }

    // MARK: Derivation

    private var loadedGraph: BrainGraphResponse? {
        if case let .loaded(graph) = store.state { return graph }
        return nil
    }

    /// Changes with every response that lands, even one that looks like the
    /// last (same counts, same `generatedAt`).
    private var derivationKey: String {
        BrainTabState.derivationKey(
            loadSerial: loadedGraph == nil ? nil : store.loadSerial, knownVaults: store.knownVaults.map(\.id)
        )
    }

    private var colourOrder: [String] {
        filters.colourBy == .vault ? store.knownVaults.map(\.id.uuidString) : legend.keys.map(\.key)
    }

    /// `visible`, then the selection pruned to it, then the focus point
    /// selected once and the colour legend.
    private func rederive() {
        guard let graph = loadedGraph else {
            visible = nil
            legend = ([], 0)
            return
        }
        let next = BrainGraphModel.visible(graph, filters: filters)
        visible = next
        let ids = Set(next.index.byID.keys)
        selection.prune(visible: ids)
        if let id = BrainTabState.focusToSelect(focus: focus, selectedFor: focusSelectedFor, visibleIDs: ids) {
            selection.selectGroup([id], additive: false)
            focusSelectedFor = id
        }
        let labels = Dictionary(graph.nodes.map { ($0.id, $0.label) }, uniquingKeysWith: { a, _ in a })
        legend = BrainGraphModel.colourLegend(next, by: filters.colourBy) { labels[$0] }
    }
}

// MARK: - Bar pieces

/// The quiet line under the navigation bar.
private struct BrainStatusBar: View {
    @Environment(\.lvPalette) private var palette

    let line: BrainStatusLine
    let refreshing: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: LVSpacing.sm) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: LVSpacing.sm) { texts }
                    VStack(alignment: .leading, spacing: LVSpacing.hairline) { texts }
                }
                Spacer(minLength: 0)
                if refreshing {
                    // The graph stays; this says a newer one is on its way.
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Updating the graph")
                        .accessibilityAddTraits(.updatesFrequently)
                        .accessibilityIdentifier("brain.status.refreshing")
                }
            }
            if let notice = line.notice {
                // Notice and reason on the left, Retry at the end: the
                // button keeps a full 44 pt target without padding the
                // line out.
                HStack(spacing: LVSpacing.sm) {
                    VStack(alignment: .leading, spacing: LVSpacing.hairline) {
                        Text(notice)
                            .foregroundStyle(palette.textPrimary)
                        if let reason = line.reason {
                            Text(reason)
                                .foregroundStyle(palette.textSecondary)
                                .accessibilityHidden(true)
                        }
                    }
                    Spacer(minLength: 0)
                    if line.offersRetry {
                        Button(action: retry) {
                            Text(BrainTabState.retryTitle)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .disabled(refreshing)
                            .accessibilityIdentifier("brain.status.retry")
                            .accessibilityHint(line.reason ?? "")
                    }
                }
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LVSpacing.base)
        .padding(.vertical, LVSpacing.xs)
        // The canvas's own ground: since iOS 26 the bar above has no
        // material at rest, and a material strip here read as a band.
        .background(palette.backgroundBase)
    }

    @ViewBuilder
    private var texts: some View {
        if let counts = line.counts {
            Text(counts)
                .foregroundStyle(palette.textSecondary)
                .accessibilityIdentifier("brain.status.counts")
        }
        if let truncated = line.truncated {
            Text(truncated)
                .foregroundStyle(palette.textSecondary)
        }
    }
}

/// The screen's primary action, with a count of changed settings.
private struct BrainFiltersButton: View {
    @Environment(\.lvPalette) private var palette

    let changed: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: changed > 0
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
                .overlay(alignment: .topTrailing) {
                    if changed > 0 {
                        Text("\(changed)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(palette.onPrimary)
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(palette.primary))
                            .offset(x: 8, y: -6)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }
                }
        }
        .accessibilityLabel(changed > 0 ? "Filters, \(changed) changed" : "Filters")
        .accessibilityIdentifier("brain.filters")
    }
}
