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
    @Environment(\.lvPalette) private var palette

    private static let initialGraphLimit = 200
    private static let edgeKindOrder: [MemoryEdgeKindDTO] = [.wikilink, .tag, .space, .semantic, .temporal]

    @State private var vm: BrainGraphViewModel
    @State private var reasoningViewModel: KnowledgeReasoningViewModel
    @State private var reloadTask: Task<Void, Never>?
    @State private var showReasoning = false

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
                // HER-255 — title + mascot now live in the global app header
                // (MainTabView). Keep the inline navbar only for the refresh
                // action below.
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Reason", systemImage: "point.3.connected.trianglepath.dotted") {
                            showReasoning = true
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            reloadTask?.cancel()
                            Task { await loadGraph() }
                        } label: {
                            LVIconView(.arrowClockwise)
                        }
                        .disabled(isLoading)
                    }
                }
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
        case .idle, .loading:
            loadingState
        case let .loaded(graph) where graph.nodes.isEmpty:
            emptyState
        case let .loaded(graph):
            ZStack(alignment: .bottom) {
                // HER-235 3D viz — RealityKit orbitable cluster (iOS 18+); the 2D
                // Canvas remains the fallback for older OSes.
                if #available(iOS 18.0, *) {
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

                GraphLegend(
                    activeEdgeKinds: $activeEdgeKinds,
                    showWikiPages: $showWikiPages,
                    hasWikiPages: graph.nodes.contains { $0.kind == .wikiPage }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 90) // clear the floating tab bar
            }
        case let .failed(message):
            errorState(message)
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

    private var emptyState: some View {
        LVEmptyState(
            mascot: .thinking,
            headline: "No memory graph yet.",
            supporting: "Capture or save memories to grow your brain.",
            backgroundImage: "Lumina/Backgrounds/neural-network"
        )
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
            Button("Try again") { Task { await vm.load() } }
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
            .padding(.horizontal, 4)
        }
    }

    private func toggle(_ kind: MemoryEdgeKindDTO) {
        if activeEdgeKinds.contains(kind) {
            activeEdgeKinds.remove(kind)
        } else {
            activeEdgeKinds.insert(kind)
        }
    }

    private func chip(label: String, color: Color, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(color.opacity(isOn ? 0.6 : 0.0), lineWidth: 1))
            .foregroundStyle(isOn ? palette.textPrimary : palette.textSecondary)
            .opacity(isOn ? 1.0 : 0.5)
        }
        .buttonStyle(.plain)
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
