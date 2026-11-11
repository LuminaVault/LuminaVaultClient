// The Brain tab: one graph of notes and memories across every vault. This view
// wires the store (when to ask the server), the model (what is visible), the
// selection and the 2D canvas, and owns no rules of its own: which card shows,
// the badge, the status line and the request come from `BrainTabState`.
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

    @State private var searchText = ""
    @State private var searchPresented = false
    @State private var centre: BrainCentreRequest?
    @State private var showFilters = false
    @State private var showList = false
    @State private var showCapture = false

    private let savedView: BrainViewChoice?
    private let prefsDefaults: UserDefaults?

    init(client: any BrainGraphClientProtocol, focus: String? = nil, prefs: UserDefaults? = .standard) {
        let stored = BrainPrefs.load(from: prefs)
        _store = State(initialValue: BrainGraphStore(client: client))
        _filters = State(initialValue: stored.filters)
        _similarAsked = State(initialValue: BrainTabState.similarAsked(previously: false, filters: stored.filters))
        _focus = State(initialValue: focus)
        savedView = stored.view
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
                .onChange(of: graphKey, initial: true) { rederive() }
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
            if let visible { canvas(visible) }
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

    private func canvas(_ visible: VisibleBrainGraph) -> some View {
        let theme = BrainGraphTheme(palette: palette, scheme: scheme)
        let by = filters.colourBy
        let order = colourOrder
        let index = visible.index
        return BrainGraphCanvas(
            graph: visible,
            highlight: selection.highlight(index: index),
            colourOf: { node in
                theme.categoryColour(for: BrainGraphModel.colourKey(node, by: by, index: index), order: order)
            },
            onTap: { id, additive in selection.click(id, additive: additive) },
            onBackgroundTap: { selection.clear() },
            // Opening a point is the tray's job.
            onOpen: { _ in },
            centreOn: centre
        )
        .accessibilityIdentifier("brain.canvas")
        .accessibilityValue(BrainTabState.selectionSummary(selection.selected, index: index))
    }

    private var emptyCard: some View {
        ScrollView {
            VStack(spacing: LVSpacing.base) {
                LVEmptyState(
                    mascot: .thinking,
                    headline: BrainTabState.emptyHeadline,
                    supporting: BrainTabState.emptySupporting
                )
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
        if let visible, card == .graph || card == .nothingMatches {
            BrainStatusBar(
                line: BrainTabState.statusLine(
                    visible: visible,
                    truncated: store.truncatedCount != nil,
                    stale: store.stale,
                    rateLimited: store.rateLimited,
                    refreshError: store.refreshError
                ),
                refreshing: store.refreshing,
                retry: { store.retry() }
            )
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
            BrainFiltersButton(changed: BrainTabState.badgeCount(filters)) { showFilters = true }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("List", systemImage: "list.bullet") { showList = true }
                Button("Reload", systemImage: "arrow.clockwise") { store.retry() }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .accessibilityIdentifier("brain.more")
        }
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

    // MARK: Sheets

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

    /// Changes whenever a different response is on screen (or none).
    private var graphKey: String {
        guard let graph = loadedGraph else { return "none" }
        let known = store.knownVaults.map(\.id.uuidString).joined(separator: ",")
        return "\(graph.generatedAt.timeIntervalSince1970)|\(graph.nodes.count)|\(graph.edges.count)|\(known)"
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
                HStack(spacing: LVSpacing.sm) {
                    Text(notice)
                        .foregroundStyle(palette.textPrimary)
                    if line.offersRetry {
                        Button(BrainTabState.retryTitle, action: retry)
                            .disabled(refreshing)
                            .accessibilityIdentifier("brain.status.retry")
                            .accessibilityHint(line.reason ?? "")
                    }
                }
                if let reason = line.reason {
                    Text(reason)
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityHidden(true)
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
        Text(line.counts)
            .foregroundStyle(palette.textSecondary)
            .accessibilityIdentifier("brain.status.counts")
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
