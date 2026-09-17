// LuminaVaultClient/LuminaVaultClient/Features/Brain/BrainTabView.swift
//
// HER-235 — root view for the Brain tab. Owns the view-model, runs the
// initial fetch on appear, and routes graph node taps through the detail
// sheet. The sci-fi background (nebula + star field) comes from the
// existing `.lvBackground()` modifier so the graph sits naturally inside
// the app's visual identity.

import LuminaVaultShared
import SwiftUI

struct BrainTabView: View {
    private enum GraphLayer: String, CaseIterable, Identifiable {
        case knowledge = "Knowledge"
        case memories = "Memories"

        var id: Self {
            self
        }
    }

    @Environment(\.lvPalette) private var palette

    private static let initialGraphLimit = 200
    private static let edgeKindOrder: [MemoryEdgeKindDTO] = [.wikilink, .tag, .space, .semantic, .temporal]

    @State private var vm: BrainGraphViewModel
    @State private var reasoningViewModel: KnowledgeReasoningViewModel
    @State private var reloadTask: Task<Void, Never>?
    @State private var showReasoning = false
    /// Prefer Memories until Knowledge has nodes — most tenants land empty
    /// on Knowledge (confidence floor / extraction lag) and read as "broken".
    @State private var graphLayer: GraphLayer = .memories
    @State private var didAutoPickLayer = false

    /// Loads a single memory's full content when a memory node is opened
    /// (HER-235 open-on-click). Passed through to `BrainNodeDetailSheet`.
    private let memoryClient: (any MemoryClientProtocol)?

    /// Client-side edge-kind filter. The server returns every kind by
    /// default; toggling a chip hides that kind in-place with no refetch.
    /// Memory-centric reframe: `.temporal` starts OFF (its day-chains add
    /// hairball noise to the knowledge network); still toggleable.
    @State private var activeEdgeKinds: Set<MemoryEdgeKindDTO> = [
        .wikilink, .tag, .space, .semantic,
    ]
    /// Source nodes = the user's captures (notes, saved links, images). They
    /// start visible so captured content shows on the graph, but render as
    /// small dim satellites (see `BrainGraphEngine`) so memories stay primary.
    /// `filtered(_:)` drops them and any edge touching them with no refetch.
    @State private var showWikiPages = true

    init(
        client: any MemoryGraphClientProtocol,
        knowledgeClient: any KnowledgeGraphClientProtocol,
        memoryClient: (any MemoryClientProtocol)? = nil
    ) {
        _vm = State(initialValue: BrainGraphViewModel(client: client))
        _reasoningViewModel = State(initialValue: KnowledgeReasoningViewModel(client: knowledgeClient))
        self.memoryClient = memoryClient
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Brain")
                .navigationBarTitleDisplayMode(.inline)
                // The graph's own controls belong to the navigation bar and a
                // bottom bar, not to buttons floating over the canvas: the
                // native tab bar already owns that corner of the screen.
                .safeAreaInset(edge: .bottom) { filterBar }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Reason", systemImage: "point.3.connected.trianglepath.dotted") {
                            showReasoning = true
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        graphLayerPicker
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            reloadTask?.cancel()
                            Task { await loadGraph() }
                        } label: {
                            LVIconView(.arrowClockwise, label: "Reload graph")
                        }
                        .disabled(isLoading)
                    }
                }
                // Declared inside the stack, beside the toolbar above: a
                // `.toolbar` on the view that *contains* a `NavigationStack`
                // has no bar to attach to and is silently dropped.
                .captureToolbarItem()
                .task { await loadGraph() }
                .onChange(of: showWikiPages) { _, _ in scheduleGraphReload() }
                .onChange(of: activeEdgeKinds) { _, _ in scheduleGraphReload() }
                .onDisappear { reloadTask?.cancel() }
                .sheet(item: selectedBinding) { node in
                    BrainNodeDetailSheet(node: node, memoryClient: memoryClient)
                }
                .sheet(isPresented: $showReasoning) {
                    KnowledgeReasoningSheet(viewModel: reasoningViewModel, memoryClient: memoryClient)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            loadingState
        case .idle:
            // `.idle` after `.task { loadGraph() }` has run means the load was
            // aborted, not that it is still in flight. Rendering it as
            // `loadingState` is what made the Brain tab spin on "Building your
            // brain…" forever when TLS pinning cancelled every request.
            idleState
        case let .loaded(graph):
            Group {
                if graphLayer == .knowledge {
                    knowledgeGraphContent
                } else if graph.nodes.isEmpty {
                    emptyState
                } else if #available(iOS 18.0, *) {
                    BrainGraphRealityView(graph: filtered(graph)) { id in
                        vm.selectedNodeID = id
                    }
                    .lvBackground()
                } else {
                    BrainGraphCanvas(graph: filtered(graph)) { id in
                        vm.selectedNodeID = id
                    }
                    .lvBackground()
                }
            }
            .onAppear { pickInitialLayerIfNeeded(memoryGraph: graph) }
            .onChange(of: reasoningViewModel.graphState) { _, _ in
                pickInitialLayerIfNeeded(memoryGraph: graph)
            }
        case let .failed(message):
            // Memory failure must not own the whole tab — Knowledge may still
            // work, and the layer picker in the bar is the way back to it.
            if graphLayer == .knowledge {
                knowledgeGraphContent
            } else {
                errorState(message)
            }
        }
    }

    /// The bottom bar under the graph: the edge-kind filters on the memory
    /// layer, the selection/explain controls on the knowledge one. Empty —
    /// and therefore absent — until there is a graph to filter.
    @ViewBuilder
    private var filterBar: some View {
        if case let .loaded(graph) = vm.state {
            if graphLayer == .knowledge {
                barStrip {
                    KnowledgeSelectionBar(viewModel: reasoningViewModel) {
                        showReasoning = true
                    }
                }
            } else if !graph.nodes.isEmpty {
                barStrip {
                    GraphLegend(
                        activeEdgeKinds: $activeEdgeKinds,
                        showWikiPages: $showWikiPages,
                        hasWikiPages: graph.nodes.contains { $0.kind == .wikiPage }
                    )
                }
            }
        }
    }

    /// Standard bar chrome. Horizontal padding is the content's own so a
    /// horizontally scrolling row can still run to both edges.
    private func barStrip(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.bar)
    }

    private func pickInitialLayerIfNeeded(memoryGraph: MemoryGraphResponse) {
        guard !didAutoPickLayer else { return }
        switch reasoningViewModel.graphState {
        case let .ready(knowledge) where !knowledge.nodes.isEmpty:
            graphLayer = .knowledge
            didAutoPickLayer = true
        case .ready, .unavailable:
            graphLayer = memoryGraph.nodes.isEmpty ? .knowledge : .memories
            didAutoPickLayer = true
        case .idle, .loading:
            break
        }
    }

    // MARK: - States

    private var isLoading: Bool {
        if case .loading = vm.state {
            return true
        }
        return false
    }

    private var requestKinds: [MemoryEdgeKindDTO] {
        Self.edgeKindOrder.filter { activeEdgeKinds.contains($0) }
    }

    private func loadGraph() async {
        await vm.load(
            limit: Self.initialGraphLimit,
            includeWikiPages: showWikiPages,
            kinds: requestKinds
        )
        await reasoningViewModel.load()
    }

    @ViewBuilder
    private var knowledgeGraphContent: some View {
        switch reasoningViewModel.graphState {
        case .idle, .loading:
            loadingState
        case let .unavailable(message):
            VStack(spacing: 12) {
                LVIconView(.exclamationmarkTriangleFill, size: 38, tint: palette.accent)
                Text("Reasoning graph unavailable")
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
                Text(message)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.textSecondary)
                Button("Show memory graph") { graphLayer = .memories }
                    .buttonStyle(.borderedProminent)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .lvBackground()
        case let .ready(graph) where graph.nodes.isEmpty:
            VStack(spacing: 16) {
                LVEmptyState(
                    mascot: .thinking,
                    headline: "No reasoning graph yet.",
                    supporting: "New memories are converted into claims, entities, events, and evidence-backed connections.",
                    backgroundImage: "Lumina/Backgrounds/neural-network"
                )
                Button("Show memory graph") { graphLayer = .memories }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .lvBackground()
        case let .ready(graph):
            let projected = KnowledgeGraphProjection.make(
                graph: graph,
                focusedPath: reasoningViewModel.selectedPath,
                selectedNodeIDs: Set(reasoningViewModel.selectedNodeIDs)
            )
            let identity = "\(reasoningViewModel.selectedPathID?.uuidString ?? "all")-\(reasoningViewModel.selectedNodeIDs.map(\.uuidString).joined())"
            if projected.nodes.isEmpty {
                VStack(spacing: 12) {
                    Text("Nothing to show for this path.")
                        .font(.headline)
                        .foregroundStyle(palette.textPrimary)
                    Button("Show all memories") { graphLayer = .memories }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .lvBackground()
            } else if #available(iOS 18.0, *) {
                BrainGraphRealityView(graph: projected, onSelect: selectKnowledgeNode)
                    .id(identity)
                    .lvBackground()
            } else {
                BrainGraphCanvas(graph: projected, onSelect: selectKnowledgeNode)
                    .id(identity)
                    .lvBackground()
            }
        }
    }

    private var graphLayerPicker: some View {
        Picker("Graph layer", selection: $graphLayer) {
            ForEach(GraphLayer.allCases) { layer in
                Text(layer.rawValue).tag(layer)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("Switch between the reasoning graph and captured memories")
    }

    private func selectKnowledgeNode(_ id: UUID) {
        Task {
            let explained = await reasoningViewModel.selectNode(id)
            if explained {
                showReasoning = true
            }
        }
    }

    private func scheduleGraphReload() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await loadGraph()
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(palette.primary)
            Text("Building your brain…")
                .font(.callout)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
    }

    /// Shown when a load ended without producing a graph and without a hard
    /// error — an interrupted first load. Offers a way out instead of an
    /// indefinite spinner.
    private var idleState: some View {
        VStack(spacing: 12) {
            LVIconView(.exclamationmarkTriangleFill, size: 42, tint: palette.accent)
            Text("Brain didn't finish loading")
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Text("The request was interrupted before your graph arrived.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 32)
            Button("Try again") { Task { await loadGraph() } }
                .buttonStyle(.borderedProminent)
                .tint(palette.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            LVEmptyState(
                mascot: .thinking,
                headline: "No memory graph yet.",
                supporting: "Capture or save memories to grow your brain.",
                backgroundImage: "Lumina/Backgrounds/neural-network"
            )
            Button("Check reasoning graph") { graphLayer = .knowledge }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            LVIconView(.exclamationmarkTriangleFill, size: 42, tint: palette.accent)
            Text("Couldn't load your brain")
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 32)
            Button("Try again") { Task { await loadGraph() } }
                .buttonStyle(.borderedProminent)
                .tint(palette.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
    }

    // MARK: - Filtering

    /// Applies the in-place node/edge filters. Drops wiki-page nodes when
    /// hidden, then keeps only edges of an active kind whose endpoints both
    /// survive — so no edge dangles to a filtered-out node.
    private func filtered(_ graph: MemoryGraphResponse) -> MemoryGraphResponse {
        var nodes = graph.nodes
        if !showWikiPages {
            nodes = nodes.filter { $0.kind != .wikiPage }
        }
        // Space hubs only read as hubs with their star edges; drop them when
        // the Space edge kind is off so no orphan hubs float.
        if !activeEdgeKinds.contains(.space) {
            nodes = nodes.filter { $0.kind != .space }
        }
        let liveIDs = Set(nodes.map(\.id))
        let edges = graph.edges.filter {
            activeEdgeKinds.contains($0.kind) && liveIDs.contains($0.from) && liveIDs.contains($0.to)
        }
        return MemoryGraphResponse(nodes: nodes, edges: edges, generatedAt: graph.generatedAt)
    }

    // MARK: - Sheet binding

    /// Bridges `selectedNodeID` + the current graph into an `Identifiable`
    /// node for the sheet API.
    private var selectedBinding: Binding<MemoryGraphNodeDTO?> {
        Binding(
            get: { vm.selectedNodeID.flatMap(vm.node(for:)) },
            set: { node in vm.selectedNodeID = node?.id }
        )
    }
}

// MARK: - Knowledge selection

private struct KnowledgeSelectionBar: View {
    @Environment(\.lvPalette) private var palette

    let viewModel: KnowledgeReasoningViewModel
    let showExplanation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                legendDot("Claims", color: palette.accent)
                legendDot("Events", color: palette.secondary)
                legendDot("Entities", color: palette.primary)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                legendDot("Supports", color: palette.primary)
                legendDot("Contradicts", color: Color(red: 0.98, green: 0.32, blue: 0.42))
                legendDot("Causal", color: palette.textSecondary)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(palette.primary)
                Text(selectionText)
                    .font(.caption)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if viewModel.selectedPathID != nil {
                    Button("All") { viewModel.selectPath(nil) }
                        .font(.caption.weight(.semibold))
                        .accessibilityLabel("Show all knowledge graph paths")
                }
                if viewModel.explanation != nil {
                    Button("Explain connection", action: showExplanation)
                        .font(.caption.weight(.semibold))
                        .accessibilityLabel("Explain this connection")
                }
                if !viewModel.selectedNodeIDs.isEmpty {
                    Button {
                        viewModel.clearSelection()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel("Clear selected knowledge nodes")
                }
            }
        }
        // No card of its own: it sits on the bottom bar's material.
        .padding(.horizontal, 16)
    }

    private var selectionText: String {
        switch viewModel.selectedNodes.count {
        case 0: "Select two nodes to explain their connection"
        case 1: "\(viewModel.selectedNodes[0].label) selected — choose another"
        default: viewModel.selectedNodes.map(\.label).joined(separator: " ↔ ")
        }
    }

    private func legendDot(_ label: String, color: Color) -> some View {
        Label {
            Text(label).font(.caption2)
        } icon: {
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .foregroundStyle(palette.textSecondary)
    }
}

// MARK: - Legend

/// Compact, glassy filter legend pinned to the bottom of the graph. Each
/// chip both documents the colour channel and toggles that edge kind.
private struct GraphLegend: View {
    @Environment(\.lvPalette) private var palette

    @Binding var activeEdgeKinds: Set<MemoryEdgeKindDTO>
    @Binding var showWikiPages: Bool
    let hasWikiPages: Bool

    private static let order: [MemoryEdgeKindDTO] = [.wikilink, .tag, .space, .semantic, .temporal]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if hasWikiPages {
                    // "Sources" = the raw vault-file pages behind your memories
                    // (the wire still calls these `wikiPage`; cosmetic rename).
                    chip(
                        label: "Sources",
                        color: palette.accent,
                        isOn: showWikiPages
                    ) { showWikiPages.toggle() }
                }
                ForEach(Self.order, id: \.self) { kind in
                    chip(
                        label: Self.label(for: kind),
                        color: color(for: kind),
                        isOn: activeEdgeKinds.contains(kind)
                    ) { toggle(kind) }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func toggle(_ kind: MemoryEdgeKindDTO) {
        if activeEdgeKinds.contains(kind) {
            activeEdgeKinds.remove(kind)
        } else {
            activeEdgeKinds.insert(kind)
        }
    }

    /// A stock bordered capsule. The dot keeps the legend's job — naming the
    /// colour channel each edge kind is drawn in — while the tint carries
    /// the on/off state the way any iOS filter chip does.
    private func chip(label: String, color: Color, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
            }
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(isOn ? color : Color.secondary)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func color(for kind: MemoryEdgeKindDTO) -> Color {
        switch kind {
        case .wikilink: return palette.accent
        case .tag: return palette.accent.opacity(0.7)
        case .space: return palette.secondary
        case .semantic: return palette.primary
        case .temporal: return palette.textSecondary
        }
    }

    private static func label(for kind: MemoryEdgeKindDTO) -> String {
        switch kind {
        case .wikilink: return "Links"
        case .tag: return "Tags"
        case .space: return "Spaces"
        case .semantic: return "Similar"
        case .temporal: return "Time"
        }
    }
}
