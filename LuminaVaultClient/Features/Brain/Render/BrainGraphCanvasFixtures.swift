// Debug-only graphs for the 2D canvas's previews and snapshot tests: a
// 25-point and a 600-point graph, each already laid out to rest, so a
// `Canvas` inside `ImageRenderer` or a preview can draw it at once.

#if DEBUG
import LuminaVaultShared
import SwiftUI

nonisolated struct BrainGraphCanvasFixture: Sendable {
    var graph: VisibleBrainGraph
    var snapshot: LayoutSnapshot
    /// Vault ids in a stable order, for `BrainGraphTheme.categoryColour`.
    var vaultOrder: [String]

    /// Colour by vault, as the screen does by default.
    func colourOf(_ theme: BrainGraphTheme) -> (BrainGraphNodeDTO) -> Color {
        let order = vaultOrder
        let index = graph.index
        return { node in
            theme.categoryColour(for: BrainGraphModel.colourKey(node, by: .vault, index: index), order: order)
        }
    }

    /// The id of the heaviest note, a natural point to select.
    var heaviestItem: String {
        graph.nodes.filter { !BrainGraphModel.isHub($0) }.max { $0.weight < $1.weight }?.id ?? ""
    }

    static let small = make(items: 21, vaults: 2, tags: 3, authors: 1, seed: 7)
    static let large = make(items: 560, vaults: 4, tags: 30, authors: 10, seed: 11)

    private static let words = [
        "Graph", "Notes", "Sleep", "Design", "Rust", "Swift", "Garden", "Reading", "Travel", "Budget",
        "Meeting", "Ideas", "Recipes", "Health", "Music", "Physics", "History", "Running", "Writing", "Coffee",
    ]

    /// A deterministic graph: items spread over vaults, attached to tag and
    /// author hubs, with a few direct links, then laid out to rest.
    static func make(items: Int, vaults: Int, tags: Int, authors: Int, seed: UInt64) -> BrainGraphCanvasFixture {
        var rng = seed
        func next(_ n: Int) -> Int {
            rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((rng >> 33) % UInt64(max(1, n)))
        }
        let vaultIDs = (0 ..< vaults).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", 0xA0 + $0)) ?? UUID() }
        var nodes: [BrainGraphNodeDTO] = []
        var edges: [BrainGraphEdgeDTO] = []
        var degree: [String: Int] = [:]
        func link(_ from: String, _ to: String, _ kind: BrainLinkKindDTO) {
            edges.append(BrainGraphEdgeDTO(from: from, to: to, kind: kind))
            degree[from, default: 0] += 1
            degree[to, default: 0] += 1
        }
        let itemIDs = (0 ..< items).map { String(format: "00000000-0000-0000-0001-%012X", $0) }
        let tagIDs = (0 ..< tags).map { "tag:\(words[$0 % words.count].lowercased())\($0 / words.count == 0 ? "" : "-\($0 / words.count)")" }
        let authorIDs = (0 ..< authors).map { String(format: "author:user:00000000-0000-0000-0002-%012X", $0) }
        for (i, id) in itemIDs.enumerated() {
            link(id, tagIDs[next(tags)], .tag)
            if next(3) == 0 { link(id, tagIDs[next(tags)], .tag) }
            link(id, authorIDs[next(authors)], .author)
            if i > 0, next(2) == 0 { link(id, itemIDs[next(i)], .link) }
        }
        var titles: [String: String] = [:]
        for (i, id) in itemIDs.enumerated() {
            let a = words[next(words.count)], b = words[next(words.count)]
            titles[id] = i.isMultiple(of: 7) ? "\(a) and \(b.lowercased()): a longer note about both" : "\(a) \(b.lowercased())"
        }
        for (i, id) in itemIDs.enumerated() {
            nodes.append(BrainGraphNodeDTO(
                id: id, kind: i % 4 == 3 ? .memory : .note, label: titles[id] ?? id,
                vaultID: vaultIDs[i % vaults], weight: degree[id] ?? 0
            ))
        }
        for id in tagIDs where (degree[id] ?? 0) >= 2 {
            nodes.append(BrainGraphNodeDTO(id: id, kind: .tag, label: String(id.dropFirst(4)), weight: degree[id] ?? 0))
        }
        for (i, id) in authorIDs.enumerated() where (degree[id] ?? 0) >= 2 {
            nodes.append(BrainGraphNodeDTO(id: id, kind: .author, label: "Author \(i + 1)", weight: degree[id] ?? 0))
        }
        let alive = Set(nodes.map(\.id))
        edges = edges.filter { alive.contains($0.from) && alive.contains($0.to) }

        var index = BrainGraphIndex()
        for n in nodes {
            index.byID[n.id] = n
            index.neighbours[n.id] = []
            index.edgesOf[n.id] = []
        }
        for e in edges {
            index.neighbours[e.from]?.insert(e.to)
            index.neighbours[e.to]?.insert(e.from)
            index.edgesOf[e.from]?.append(e)
            index.edgesOf[e.to]?.append(e)
        }
        let graph = VisibleBrainGraph(nodes: nodes, edges: edges, index: index)

        var simulation = ForceSimulation2D()
        simulation.setGraph(graph)
        var ticks = 0
        while simulation.tick(), ticks < 1000 { ticks += 1 }
        let snapshot = LayoutSnapshot(
            ids: simulation.nodes.map(\.id), points: simulation.positions, settled: true, generation: 1
        )
        return BrainGraphCanvasFixture(graph: graph, snapshot: snapshot, vaultOrder: vaultIDs.map(\.uuidString))
    }
}

/// The canvas on a fixture, coloured from the environment's palette, never
/// starting a layout. For previews and snapshot tests.
struct BrainGraphCanvasFixtureHost: View {
    var fixture: BrainGraphCanvasFixture
    var selected: [String] = []
    var viewport: BrainGraphViewport?

    @Environment(\.lvPalette) private var palette
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = BrainGraphTheme(palette: palette, scheme: scheme)
        BrainGraphCanvas(
            graph: fixture.graph,
            highlight: BrainHighlight(
                selected: Set(selected),
                lit: selected.isEmpty ? nil : BrainGraphModel.litSet(fixture.graph.index, ids: selected)
            ),
            colourOf: fixture.colourOf(theme),
            onTap: { _, _ in },
            onBackgroundTap: {},
            onOpen: { _ in },
            fixedSnapshot: fixture.snapshot,
            fixedViewport: viewport
        )
    }
}
#endif
