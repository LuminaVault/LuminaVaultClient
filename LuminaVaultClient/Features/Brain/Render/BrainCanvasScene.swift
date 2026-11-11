// What the 2D Brain canvas draws, and the drawing itself. `BrainCanvasScene`
// is built once per change of the visible graph or its colours (never per
// frame): radii, hub flags, truncated labels, edges by index, the weight order
// labels are offered in, and the points grouped by colour so a frame fills one
// path per colour. `BrainCanvasPainter` paints one frame of it into a
// `GraphicsContext`, as the web 2D renderer's `draw` does.

import LuminaVaultShared
import SwiftUI

nonisolated struct BrainCanvasScene: Sendable {
    nonisolated struct Edge: Equatable, Sendable {
        var a: Int
        var b: Int
        var kind: BrainLinkKindDTO
    }

    nonisolated struct Fill: Sendable {
        var colour: Color
        var members: [Int]
    }

    /// Graph order. Every per-point array below is indexed the same way.
    let ids: [String]
    let index: [String: Int]
    let radius: [CGFloat]
    let isHub: [Bool]
    let text: [String]
    let weight: [Int]
    let edges: [Edge]
    /// Heaviest first; ties keep graph order.
    let byWeight: [Int]
    let topTenth: Int
    /// Items (not hubs) by colour, colours in first-seen order.
    let fills: [Fill]
    let hubs: [Int]
    /// Notes and memories: what the accessibility label counts.
    let itemCount: Int
    /// Changes when the points, their weights or kinds, or the edges change;
    /// not when only colours or labels do. A new key means a new layout.
    let layoutKey: Int

    static let empty = BrainCanvasScene(graph: VisibleBrainGraph(nodes: [], edges: [], index: BrainGraphIndex())) { _ in .clear }

    init(graph: VisibleBrainGraph, colourOf: (BrainGraphNodeDTO) -> Color) {
        var ids: [String] = []
        var index: [String: Int] = [:]
        var radius: [CGFloat] = []
        var isHub: [Bool] = []
        var text: [String] = []
        var weight: [Int] = []
        var fills: [Fill] = []
        var fillAt: [Color: Int] = [:]
        var hubs: [Int] = []
        var items = 0
        var hasher = Hasher()
        ids.reserveCapacity(graph.nodes.count)
        for node in graph.nodes where index[node.id] == nil {
            let i = ids.count
            let hub = BrainGraphModel.isHub(node)
            ids.append(node.id)
            index[node.id] = i
            radius.append(ForceSimulation2D.nodeRadius(weight: node.weight, isHub: hub))
            isHub.append(hub)
            text.append(BrainGraphCanvasLogic.truncateLabel(node.label))
            weight.append(node.weight)
            hasher.combine(node.id)
            hasher.combine(node.weight)
            hasher.combine(node.kind.rawValue)
            if hub {
                hubs.append(i)
            } else {
                items += 1
                let colour = colourOf(node)
                if let at = fillAt[colour] {
                    fills[at].members.append(i)
                } else {
                    fillAt[colour] = fills.count
                    fills.append(Fill(colour: colour, members: [i]))
                }
            }
        }
        hasher.combine(-1)
        var edges: [Edge] = []
        edges.reserveCapacity(graph.edges.count)
        for e in graph.edges where e.from != e.to {
            guard let a = index[e.from], let b = index[e.to] else { continue }
            edges.append(Edge(a: a, b: b, kind: e.kind))
            hasher.combine(a)
            hasher.combine(b)
            hasher.combine(e.kind.rawValue)
        }

        self.ids = ids
        self.index = index
        self.radius = radius
        self.isHub = isHub
        self.text = text
        self.weight = weight
        self.edges = edges
        // `sorted` is not stable; the index breaks ties so equal weights keep graph order.
        byWeight = ids.indices.sorted { weight[$0] != weight[$1] ? weight[$0] > weight[$1] : $0 < $1 }
        topTenth = BrainGraphCanvasLogic.topTenthWeight(weight)
        self.fills = fills
        self.hubs = hubs
        itemCount = items
        layoutKey = hasher.finalize()
    }

    /// The snapshot's points in scene order, by id. Points the snapshot does
    /// not have (a graph newer than the layout) are NaN and not drawn.
    func aligned(_ snapshot: LayoutSnapshot) -> [CGPoint] {
        var out = [CGPoint](repeating: CGPoint(x: CGFloat.nan, y: CGFloat.nan), count: ids.count)
        for (i, id) in snapshot.ids.enumerated() where i < snapshot.points.count {
            if let at = index[id] { out[at] = snapshot.points[i] }
        }
        return out
    }
}

/// Per-canvas scratch that survives frames: the label occupancy grid and the
/// resolved label texts, so drawing labels allocates almost nothing per frame.
@MainActor
final class BrainCanvasScratch {
    var boxes = BrainLabelBoxes(canvas: .zero)
    private var texts: [String: GraphicsContext.ResolvedText] = [:]
    private var sizes: [String: CGSize] = [:]
    private var textKey: AnyHashable?

    /// The resolved text of a label and its size. The cache is dropped when
    /// the text colour or Dynamic Type size changes.
    func text(
        _ string: String, in context: GraphicsContext, colour: Color, typeSize: DynamicTypeSize
    ) -> (GraphicsContext.ResolvedText, CGSize) {
        let key = AnyHashable([AnyHashable(colour), AnyHashable(typeSize)])
        if key != textKey {
            texts.removeAll(keepingCapacity: true)
            sizes.removeAll(keepingCapacity: true)
            textKey = key
        }
        if let t = texts[string], let s = sizes[string] { return (t, s) }
        let resolved = context.resolve(
            Text(verbatim: string).font(BrainCanvasPainter.labelFont).foregroundStyle(colour)
        )
        let size = resolved.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        texts[string] = resolved
        sizes[string] = size
        return (resolved, size)
    }
}

/// One frame's inputs.
nonisolated struct BrainCanvasFrame: Sendable {
    var scene: BrainCanvasScene
    /// In scene order; NaN for a point not laid out yet.
    var positions: [CGPoint]
    var viewport: BrainGraphViewport
    var highlight: BrainHighlight
    var theme: BrainGraphTheme
    var typeSize: DynamicTypeSize
}

/// Paints one frame. Edges and points in world units under the view transform;
/// labels in screen points on top.
@MainActor
enum BrainCanvasPainter {
    static let labelFont = LVTypography.caption.font

    static func paint(
        _ context: inout GraphicsContext, size: CGSize, frame f: BrainCanvasFrame, scratch: BrainCanvasScratch
    ) {
        // Background ourselves: hub interiors and label plates use it, so it
        // must match whatever surface the canvas sits on.
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(f.theme.background))
        guard f.positions.count == f.scene.ids.count, !f.positions.isEmpty, f.viewport.scale > 0 else { return }

        let k = f.viewport.scale
        let pad = BrainGraphCanvasLogic.maxRadius + 4 / k
        let view = f.viewport.visibleWorldRect(in: size).insetBy(dx: -pad, dy: -pad)

        var world = context
        world.concatenate(CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: f.viewport.offset.x, ty: f.viewport.offset.y))
        paintEdges(&world, f, view: view)
        paintPoints(&world, f, view: view)
        paintLabels(&context, size: size, f, scratch: scratch)
    }

    private static func paintEdges(_ g: inout GraphicsContext, _ f: BrainCanvasFrame, view: CGRect) {
        let (k, scene, positions, highlight, theme) = (f.viewport.scale, f.scene, f.positions, f.highlight, f.theme)
        let kinds = BrainLinkKindDTO.allCases
        var normal = [Path](repeating: Path(), count: kinds.count)
        var bright = [Path](repeating: Path(), count: kinds.count)
        var dim = Path()
        let lit = highlight.lit
        for e in scene.edges {
            let a = positions[e.a], b = positions[e.b]
            guard a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite else { continue }
            if max(a.x, b.x) < view.minX || min(a.x, b.x) > view.maxX { continue }
            if max(a.y, b.y) < view.minY || min(a.y, b.y) > view.maxY { continue }
            let slot = kinds.firstIndex(of: e.kind) ?? 0
            if let lit {
                let ida = scene.ids[e.a], idb = scene.ids[e.b]
                if lit.contains(ida), lit.contains(idb),
                   highlight.selected.contains(ida) || highlight.selected.contains(idb) {
                    bright[slot].move(to: a)
                    bright[slot].addLine(to: b)
                } else {
                    dim.move(to: a)
                    dim.addLine(to: b)
                }
            } else {
                normal[slot].move(to: a)
                normal[slot].addLine(to: b)
            }
        }
        let width = BrainGraphCanvasLogic.edgeWidth / k
        g.stroke(dim, with: .color(theme.dim.opacity(BrainGraphCanvasLogic.dimAlpha)), lineWidth: width)
        for (paths, alpha) in [(normal, BrainGraphCanvasLogic.edgeAlpha), (bright, BrainGraphCanvasLogic.litEdgeAlpha)] {
            for (slot, path) in paths.enumerated() where !path.isEmpty {
                g.stroke(path, with: .color(theme.link(kinds[slot]).opacity(alpha)), lineWidth: width)
            }
        }
    }

    private static func circle(_ path: inout Path, _ p: CGPoint, _ r: CGFloat) {
        path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    private static func paintPoints(_ g: inout GraphicsContext, _ f: BrainCanvasFrame, view: CGRect) {
        let (k, scene, positions, highlight, theme) = (f.viewport.scale, f.scene, f.positions, f.highlight, f.theme)
        let floor = BrainGraphCanvasLogic.minDrawnRadius / k
        let lit = highlight.lit
        func onScreen(_ p: CGPoint) -> Bool { view.contains(p) }
        func dimmed(_ i: Int) -> Bool { lit.map { !$0.contains(scene.ids[i]) } ?? false }

        var dim = Path()
        var dimRings = Path()
        var rings = Path()
        var fills: [(Color, Path)] = []
        fills.reserveCapacity(scene.fills.count)
        for fill in scene.fills {
            var path = Path()
            for i in fill.members {
                let p = positions[i]
                guard onScreen(p) else { continue }
                if dimmed(i) { circle(&dim, p, max(scene.radius[i], floor)) } else { circle(&path, p, max(scene.radius[i], floor)) }
            }
            fills.append((fill.colour, path))
        }
        for i in scene.hubs {
            let p = positions[i]
            guard onScreen(p) else { continue }
            if dimmed(i) { circle(&dimRings, p, max(scene.radius[i], floor)) } else { circle(&rings, p, max(scene.radius[i], floor)) }
        }

        let dimColour = theme.dim.opacity(BrainGraphCanvasLogic.dimAlpha)
        let ringWidth = BrainGraphCanvasLogic.hubRingWidth / k
        g.fill(dim, with: .color(dimColour))
        g.stroke(dimRings, with: .color(dimColour), lineWidth: ringWidth)
        for (colour, path) in fills where !path.isEmpty {
            g.fill(path, with: .color(colour))
        }
        // Hubs: rings, hollowed with the background so edges stop at the rim.
        g.fill(rings, with: .color(theme.background))
        g.stroke(rings, with: .color(theme.hub), lineWidth: ringWidth)

        var selected = Path()
        for id in highlight.selected {
            guard let i = scene.index[id] else { continue }
            let p = positions[i]
            guard onScreen(p) else { continue }
            circle(&selected, p, max(scene.radius[i], floor) + BrainGraphCanvasLogic.selectedRingGap / k)
        }
        g.stroke(selected, with: .color(theme.selection), lineWidth: BrainGraphCanvasLogic.selectedRingWidth / k)
    }

    private static func paintLabels(
        _ context: inout GraphicsContext, size: CGSize, _ f: BrainCanvasFrame, scratch: BrainCanvasScratch
    ) {
        let (v, scene, positions, highlight, theme) = (f.viewport, f.scene, f.positions, f.highlight, f.theme)
        let k = v.scale
        let lit = highlight.lit
        let selected = highlight.selected
        let reach = BrainGraphCanvasLogic.selectedRingGap + BrainGraphCanvasLogic.selectedRingWidth / 2
        func screenR(_ i: Int) -> CGFloat {
            max(scene.radius[i] * k, BrainGraphCanvasLogic.minDrawnRadius) + (selected.contains(scene.ids[i]) ? reach : 0)
        }

        // Circles claim their space first, so a label never half-covers one. A
        // small graph keeps labels off every point; a large one only off hub
        // rings and selected points, or it would lose most of its labels.
        scratch.boxes.clear(canvas: size)
        let avoidAll = BrainGraphCanvasLogic.labelsAvoidEveryPoint(pointCount: scene.ids.count)
        for i in scene.ids.indices {
            let id = scene.ids[i]
            if let lit, !lit.contains(id) { continue }
            if !avoidAll, !scene.isHub[i], !selected.contains(id) { continue }
            let p = positions[i]
            guard p.x.isFinite, p.y.isFinite else { continue }
            let c = v.screen(p)
            let r = screenR(i) + 1
            if c.x + r < 0 || c.x - r > size.width || c.y + r < 0 || c.y - r > size.height { continue }
            scratch.boxes.occupy(CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }

        var plates = Path()
        var placed: [(GraphicsContext.ResolvedText, CGPoint)] = []
        placed.reserveCapacity(64)
        let small = scene.ids.count <= BrainGraphCanvasLogic.smallGraph

        func tryLabel(_ i: Int, force: Bool) {
            let p = positions[i]
            guard p.x.isFinite, p.y.isFinite else { return }
            let c = v.screen(p)
            let r = screenR(i)
            let (text, textSize) = scratch.text(scene.text[i], in: context, colour: theme.label, typeSize: f.typeSize)
            if BrainGraphCanvasLogic.labelOffscreen(centre: c, radius: r, text: textSize, canvas: size) { return }
            let spots = BrainGraphCanvasLogic.labelSpots(centre: c, radius: r, text: textSize)
            guard let at = scratch.boxes.place(spots, canvas: size, force: force) else { return }
            plates.addRoundedRect(
                in: at.rect,
                cornerSize: CGSize(width: BrainGraphCanvasLogic.labelPlateRadius, height: BrainGraphCanvasLogic.labelPlateRadius)
            )
            placed.append((text, at.text))
        }

        // Selected first (forced), then the rest heaviest first.
        if !selected.isEmpty {
            for i in scene.byWeight where placed.count < BrainGraphCanvasLogic.maxLabels && selected.contains(scene.ids[i]) {
                tryLabel(i, force: true)
            }
        }
        for i in scene.byWeight {
            guard placed.count < BrainGraphCanvasLogic.maxLabels else { break }
            let id = scene.ids[i]
            if selected.contains(id) { continue }
            let offered = BrainGraphCanvasLogic.offerLabel(
                lit: lit.map { $0.contains(id) }, weight: scene.weight[i], zoom: k, topTenth: scene.topTenth, small: small
            )
            if offered { tryLabel(i, force: false) }
        }

        // A plate rather than a halo: edges no longer show between the letters.
        context.fill(plates, with: .color(theme.background.opacity(BrainGraphCanvasLogic.labelPlateAlpha)))
        for (text, at) in placed {
            context.draw(text, at: at, anchor: .top)
        }
    }
}
