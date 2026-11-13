// The pure rules behind the 3D Constellation: what each star is (size, colour,
// label), how large it may look on screen, which lines are drawn at rest and
// which when something is lit, and how a tap finds a star on screen. Labels
// are in `ConstellationLabels`, camera framing in `ConstellationFraming`, the
// idle turn in `ConstellationIdleTurn`. A port of the web app's
// `render-3d-helpers.ts`, with the same numbers except the hit floor (22 pt
// for a finger, web 12 px for a cursor). No RealityKit, no state.

import CoreGraphics
import Foundation
import LuminaVaultShared
import simd
import SwiftUI

// MARK: - What is drawn

/// One graph as the Constellation draws it: built once per change of the
/// visible graph or its colours, never per frame. Every per-star array is
/// indexed the same way. At most `ConstellationRules.maxStars` stars.
nonisolated struct ConstellationModel: Sendable {
    nonisolated struct Edge: Equatable, Sendable {
        var a: Int
        var b: Int
        var kind: BrainLinkKindDTO
    }

    let ids: [String]
    let index: [String: Int]
    let isHub: [Bool]
    /// World radius of the star's core (or of a hub's ring).
    let radius: [Float]
    /// The weight labels are offered by: a hub's is discounted.
    let labelWeight: [Double]
    let text: [String]
    let colour: [Color]
    let edges: [Edge]
    /// The resting lines: the strongest `link` / `similar` edges, best first.
    let rest: [Int]
    /// Notes and memories: what the accessibility label counts.
    let itemCount: Int
    /// Changes when anything drawn changes: stars, sizes, colours, labels, lines.
    let key: Int
    /// Changes when the layout's input changes: the visible points, their
    /// kinds, weights and server positions, and the edges. Not colours or labels.
    let layoutKey: Int

    static let empty = ConstellationModel(graph: VisibleBrainGraph(nodes: [], edges: [], index: BrainGraphIndex())) { _ in .clear }

    init(graph: VisibleBrainGraph, colourOf: (BrainGraphNodeDTO) -> Color) {
        let kept = ConstellationRules.keptNodes(graph.nodes)
        let boost = ConstellationRules.smallGraphBoost(kept.count)
        var ids: [String] = []
        var index: [String: Int] = [:]
        var isHub: [Bool] = []
        var radius: [Float] = []
        var labelWeight: [Double] = []
        var text: [String] = []
        var colour: [Color] = []
        var weight: [Int] = []
        var items = 0
        for node in kept {
            let hub = BrainGraphModel.isHub(node)
            index[node.id] = ids.count
            ids.append(node.id)
            isHub.append(hub)
            radius.append(ConstellationRules.starRadius(weight: node.weight, isHub: hub, boost: boost))
            labelWeight.append(Double(node.weight) * (hub ? ConstellationRules.hubLabelWeight : 1))
            text.append(BrainGraphCanvasLogic.truncateLabel(node.label))
            colour.append(hub ? .clear : colourOf(node))
            weight.append(node.weight)
            if !hub { items += 1 }
        }
        var edges: [Edge] = []
        var eligible: [Bool] = []
        var scores: [Double] = []
        for e in graph.edges where e.from != e.to {
            guard let a = index[e.from], let b = index[e.to] else { continue }
            edges.append(Edge(a: a, b: b, kind: e.kind))
            eligible.append(e.kind == .link || e.kind == .similar)
            scores.append(Double(weight[a] + weight[b]) + (e.weight ?? 0))
        }
        self.ids = ids
        self.index = index
        self.isHub = isHub
        self.radius = radius
        self.labelWeight = labelWeight
        self.text = text
        self.colour = colour
        self.edges = edges
        rest = ConstellationRules.restingEdges(eligible: eligible, scores: scores)
        itemCount = items

        var drawn = Hasher()
        drawn.combine(ids)
        drawn.combine(radius)
        drawn.combine(colour)
        drawn.combine(text)
        for e in edges {
            drawn.combine(e.a)
            drawn.combine(e.b)
            drawn.combine(e.kind.rawValue)
        }
        key = drawn.finalize()
        var input = Hasher()
        for n in graph.nodes {
            input.combine(n.id)
            input.combine(n.kind.rawValue)
            input.combine(n.weight)
            input.combine(n.pos?.x)
            input.combine(n.pos?.y)
            input.combine(n.pos?.z)
        }
        input.combine(-1)
        for e in graph.edges {
            input.combine(e.from)
            input.combine(e.to)
            input.combine(e.kind.rawValue)
        }
        layoutKey = input.finalize()
    }
}

/// Which label tier a star is in: lower is offered first.
nonisolated enum ConstellationTier: Int, Comparable, Sendable {
    case selected = 0, lit, other, hidden

    static func < (a: ConstellationTier, b: ConstellationTier) -> Bool { a.rawValue < b.rawValue }
}

/// What the highlight makes of each star and which lines are drawn.
nonisolated struct ConstellationLook: Equatable, Sendable {
    var tiers: [ConstellationTier]
    /// Indices into `ConstellationModel.edges`.
    var lines: [Int]
    /// Whether `lines` is a lit neighbourhood (drawn stronger) rather than the resting set.
    var linesLit: Bool

    func isDimmed(_ i: Int) -> Bool { tiers[i] == .hidden }
}

/// Where a star is on screen, for picking and labels. `x`, `y` and `depth`
/// are NaN for a star behind the camera.
nonisolated struct ConstellationProjection: Equatable, Sendable {
    var x: [CGFloat] = []
    var y: [CGFloat] = []
    /// Distance in front of the camera along its view direction.
    var depth: [CGFloat] = []
    /// The star's core radius on screen, in points.
    var radius: [CGFloat] = []
    var size: CGSize = .zero

    var count: Int { x.count }

    func point(_ i: Int) -> CGPoint { CGPoint(x: x[i], y: y[i]) }
}

nonisolated enum ConstellationRules {
    /// The request limit: never more stars than this.
    static let maxStars = 800
    /// Resting lines: the strongest link / similar edges, at most this many.
    static let restEdgeLimit = 300
    /// A dimmed star (outside the lit set) keeps this share of its colour.
    static let dimIntensity: Double = 0.15
    /// Smallest hit radius on screen, in points: a fingertip.
    static let hitFloor: CGFloat = 22
    static let maxLabels = 24
    /// Vertical field of view, degrees.
    static let fieldOfView: Float = 50
    /// A star's sprite spans this many times its 2D radius in world units
    /// (web `STAR_SCALE`), and its visible core is `coreShare` of that.
    static let starScale = 1.2
    static let coreShare = 0.31
    /// A hub's ring is the mark itself, half its sprite, and stays small.
    static let hubShare = 0.5
    static let maxHubRadius: Float = 2.5
    /// Stars grow up to this many times as the count falls below 300.
    static let smallBoost = 1.7
    /// A hub's weight is its member count and would claim most labels.
    static let hubLabelWeight = 0.25
    /// Line opacity, at rest and lit, on a dark and on a pale background.
    static let restLineAlpha: Float = 0.18
    static let litLineAlpha: Float = 0.7
    static let lightRestLineAlpha: Float = 0.14
    static let lightLitLineAlpha: Float = 0.85
    /// A line's width on screen, in points (web: 1 px `LineSegments`).
    static let lineScreenWidth: Float = 1
    /// A star's sprite on screen, in points, at least and at most (web
    /// `MIN_STAR_PX`, `MAX_STAR_PX`, `MAX_HUB_PX`): a far star stays a visible
    /// dot, a near one never fills the view.
    static let minStarPoints: CGFloat = 5
    static let maxStarPoints: CGFloat = 58
    static let maxHubPoints: CGFloat = 15
    /// How far the camera may move (as a share of its distance to what it
    /// looks at) before the lines are rebuilt to keep their screen width.
    static let lineRebuildShare: Float = 0.15
    /// The selection ring's radius on screen, in points (web `RING_PX` / 2).
    static let ringRadius: CGFloat = 12
    /// A selection ring is at least this many times its star's radius, so a
    /// star seen close up still shows its ring.
    static let ringToStar: CGFloat = 1.4
    /// Share of a star's radius a label keeps clear of. The web keeps clear of
    /// 0.6 of a glowing sprite; a sphere has no glow, so all of it.
    static let labelClear: CGFloat = 1
    /// The far sky: dark appearance only.
    static let backdropCount = 600
    static let backdropRadius: Float = 1800
    static let backdropAlpha = 0.55
    /// Closest the camera may come to what it looks at.
    static let minDistance: Float = 12
    /// How far `centreOn` puts the camera from the star.
    static let comfortDistance: Float = 70
    static let centreSeconds: Double = 0.4
    /// Share of the points, nearest the centre first, that an automatic view frames.
    static let frameShare = 0.95
    /// Room left around the framed points, as a factor on their radius.
    static let frameMargin = 1.12
    /// Closest an automatic fit stands, so a two-point graph is not blown up.
    static let minFitDistance: Float = 140
    /// Farthest the user may zoom out (unless an automatic fit stood farther).
    static let maxDistance: Float = 600
    /// Farthest an automatic fit stands: well inside the far sky.
    static let maxFitDistance: Float = 1500

    // MARK: Stars

    /// The stars drawn: every visible point up to `maxStars`; past that the
    /// heaviest, ties in graph order, kept in graph order.
    static func keptNodes(_ nodes: [BrainGraphNodeDTO]) -> [BrainGraphNodeDTO] {
        guard nodes.count > maxStars else { return nodes }
        let keep = Set(nodes.indices.sorted {
            nodes[$0].weight != nodes[$1].weight ? nodes[$0].weight > nodes[$1].weight : $0 < $1
        }.prefix(maxStars))
        return nodes.indices.filter(keep.contains).map { nodes[$0] }
    }

    /// Small graphs are drawn larger so a handful of stars is not lost.
    static func smallGraphBoost(_ n: Int) -> Double {
        min(smallBoost, max(1, cbrt(300 / Double(max(1, n)))))
    }

    /// World radius of a star's core, or of a hub's ring: the 2D radius
    /// (heavier is larger) through the web's sprite scale.
    static func starRadius(weight: Int, isHub: Bool, boost: Double) -> Float {
        let base = Double(ForceSimulation2D.nodeRadius(weight: weight, isHub: isHub)) * starScale * boost
        if isHub { return min(maxHubRadius, Float(base * hubShare)) }
        return Float(base * coreShare)
    }

    // MARK: Size on screen

    /// A sprite's size on screen: world size over view depth, times the
    /// camera's points per world unit at depth 1, clamped (web `starPixelSize`).
    static func starPixelSize(
        _ worldSize: CGFloat, depth: CGFloat, pointsPerUnit: CGFloat, min minPoints: CGFloat, max maxPoints: CGFloat
    ) -> CGFloat {
        let px = depth > 0 ? worldSize * pointsPerUnit / depth : maxPoints
        return Swift.min(maxPoints, Swift.max(minPoints, px))
    }

    /// A star's radius on screen, in points: its sprite (core radius over
    /// `coreShare`, or a hub's over `hubShare`) clamped as the web clamps it,
    /// then back to the core. What is drawn and what a tap hits.
    static func screenRadius(worldRadius: Float, isHub: Bool, depth: CGFloat, pointsPerUnit: CGFloat) -> CGFloat {
        let share = isHub ? hubShare : coreShare
        let sprite = CGFloat(Double(worldRadius) / share)
        let top = isHub ? maxHubPoints : maxStarPoints
        return starPixelSize(sprite, depth: depth, pointsPerUnit: pointsPerUnit, min: minStarPoints, max: top) * share
    }

    /// `p` with every star's radius clamped by `screenRadius`.
    static func clampedRadii(
        _ p: ConstellationProjection, worldRadii: [Float], isHub: [Bool], pointsPerUnit: CGFloat
    ) -> ConstellationProjection {
        var out = p
        for i in 0 ..< Swift.min(p.count, worldRadii.count, isHub.count) where p.depth[i].isFinite {
            out.radius[i] = screenRadius(
                worldRadius: worldRadii[i], isHub: isHub[i], depth: p.depth[i], pointsPerUnit: pointsPerUnit
            )
        }
        return out
    }

    /// The scale a star's unit mesh needs so it is drawn `radius` points
    /// across at `depth`: its world radius when nothing is clamped.
    static func drawnScale(radius: CGFloat, depth: CGFloat, pointsPerUnit: CGFloat) -> Float {
        Float(radius * depth / pointsPerUnit)
    }

    /// A line's world width at `depth` that is `lineScreenWidth` points on screen.
    static func lineWorldWidth(depth: Float, pointsPerUnit: Float) -> Float {
        guard pointsPerUnit > 0 else { return 0 }
        return lineScreenWidth * Swift.max(depth, ConstellationCamera.near) / pointsPerUnit
    }

    /// Whether lines built for a camera at `builtEye` are too thick or thin
    /// for one at `eye`, `distance` from what it looks at.
    static func linesNeedRebuild(builtEye: SIMD3<Float>?, eye: SIMD3<Float>, distance: Float) -> Bool {
        guard let builtEye else { return true }
        return simd_distance(builtEye, eye) > lineRebuildShare * distance
    }

    // MARK: Lines

    /// The resting constellation: indices of the `limit` highest-scoring
    /// eligible edges, best first, ties by index. Chosen once per graph.
    static func restingEdges(eligible: [Bool], scores: [Double], limit: Int = restEdgeLimit) -> [Int] {
        let pool = eligible.indices.filter { eligible[$0] }
        return Array(pool.sorted { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }.prefix(limit))
    }

    /// Which edges the Constellation draws. Nothing lit: the resting set.
    /// Something lit: every edge with both ends lit and at least one end a
    /// seed (selected), as in the 2D view.
    static func constellationEdges(
        _ edges: [ConstellationModel.Edge], rest: [Int], lit: [Bool]?, seed: [Bool]?
    ) -> (indices: [Int], lit: Bool) {
        guard let lit, let seed else { return (rest, false) }
        let indices = edges.indices.filter { i in
            let e = edges[i]
            return lit[e.a] && lit[e.b] && (seed[e.a] || seed[e.b])
        }
        return (indices, true)
    }

    /// Each star's tier and the lines, from the highlight.
    static func look(_ model: ConstellationModel, highlight: BrainHighlight) -> ConstellationLook {
        let n = model.ids.count
        var tiers = [ConstellationTier](repeating: .other, count: n)
        var litFlags = [Bool](repeating: false, count: n)
        var seedFlags = [Bool](repeating: false, count: n)
        for i in 0 ..< n {
            let id = model.ids[i]
            let isLit = highlight.lit?.contains(id) ?? true
            let isSeed = highlight.selected.contains(id)
            litFlags[i] = highlight.lit != nil && isLit
            seedFlags[i] = isSeed
            tiers[i] = isSeed ? .selected : highlight.lit == nil ? .other : isLit ? .lit : .hidden
        }
        let lines = constellationEdges(
            model.edges, rest: model.rest,
            lit: highlight.lit == nil ? nil : litFlags, seed: highlight.lit == nil ? nil : seedFlags
        )
        return ConstellationLook(tiers: tiers, lines: lines.indices, linesLit: lines.lit)
    }

    static func lineAlpha(lit: Bool, light: Bool) -> Float {
        lit ? (light ? lightLitLineAlpha : litLineAlpha) : (light ? lightRestLineAlpha : restLineAlpha)
    }

    // MARK: Picking

    /// The star a finger at `at` means, or nil. A star is a candidate when the
    /// finger is within `max(radius, floor)`. Candidates are scored by
    /// distance relative to reach, so a large near star wins over a tiny far
    /// one a point closer; equal scores go to the nearer star.
    static func pickStar(_ p: ConstellationProjection, at: CGPoint, floor: CGFloat = hitFloor) -> Int? {
        var best: Int?
        var bestScore = CGFloat.infinity
        var bestDepth = CGFloat.infinity
        for i in 0 ..< p.count {
            let dx = p.x[i] - at.x, dy = p.y[i] - at.y
            let d2 = dx * dx + dy * dy
            let reach = max(p.radius[i], floor)
            guard d2 <= reach * reach else { continue }
            let score = d2.squareRoot() / reach
            let depth = p.depth[i]
            if score < bestScore - 1e-9 || (abs(score - bestScore) <= 1e-9 && depth < bestDepth) {
                best = i
                bestScore = score
                bestDepth = depth
            }
        }
        return best
    }

    /// The view is one VoiceOver element; the list is the way to browse.
    static func accessibilityLabel(itemCount: Int) -> String {
        "Constellation of \(itemCount) notes and memories. Use the list to browse."
    }
}
