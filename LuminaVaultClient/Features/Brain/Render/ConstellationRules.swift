// The pure rules behind the 3D Constellation: what each star is (size, colour,
// label), which lines are drawn at rest and which when something is lit, how a
// tap finds a star on screen, which stars get one of the 24 labels and where
// they go, when the idle turn may run, and how the camera frames the sky. A
// port of the web app's `render-3d-helpers.ts` and `render-3d-labels.ts`, with
// the same numbers except the hit floor (22 pt for a finger, web 12 px for a
// cursor). No RealityKit, no state: `BrainGraphRealityView` calls these.

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

/// One placed label: its star and its plate, both in screen points.
nonisolated struct ConstellationLabel: Equatable, Sendable, Identifiable {
    var star: Int
    var text: String
    var rect: CGRect
    var selected: Bool
    var id: Int { star }
}

/// What can happen to the camera, as far as "is it still the automatic fit" goes.
nonisolated enum ConstellationCameraEvent: Sendable {
    case freshGraph, press, userOrbit, userZoom, centreOn, programmatic, idleTurn
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
    /// Line thickness in world units: about a point at the fitted distance.
    static let lineWidth: Float = 0.3
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

    // MARK: Labels

    /// How many labels a view of this size can carry without crowding: 8 to 24.
    static func labelQuota(_ size: CGSize, max top: Int = maxLabels) -> Int {
        max(8, min(top, Int((size.width * size.height / 14000).rounded())))
    }

    /// Stars to offer a label, best first: by tier (selected, lit, other).
    /// Inside the selected and lit tiers the nearest comes first; inside the
    /// resting tier the heaviest does, nearness breaking ties. Hidden stars,
    /// stars behind the camera and stars off the view are left out.
    static func rankLabels(_ p: ConstellationProjection, tiers: [ConstellationTier], weights: [Double]) -> [Int] {
        let w = p.size.width, h = p.size.height
        let shown = (0 ..< p.count).filter { i in
            tiers[i] != .hidden && p.x[i] >= 0 && p.x[i] <= w && p.y[i] >= 0 && p.y[i] <= h
        }
        return shown.sorted { a, b in
            if tiers[a] != tiers[b] { return tiers[a] < tiers[b] }
            if tiers[a] == .other, weights[a] != weights[b] { return weights[a] > weights[b] }
            if p.depth[a] != p.depth[b] { return p.depth[a] < p.depth[b] }
            return a < b
        }
    }

    /// Chooses and places up to 24 labels (fewer in a small view): selected
    /// first, then lit, then the heaviest. Selection rings claim their space
    /// first, so no label covers one; in a small graph every star does, as the
    /// 2D view keeps labels off points. A lower-ranked label that would
    /// collide is dropped; a selected one is always placed, slid onto the view.
    /// How far a selected star's ring reaches on screen, in points.
    static func selectionReach(_ starRadius: CGFloat) -> CGFloat {
        max(ringRadius, starRadius * ringToStar)
    }

    static func placeLabels(
        _ p: ConstellationProjection,
        tiers: [ConstellationTier],
        weights: [Double],
        texts: [String],
        textSize: (String) -> CGSize
    ) -> [ConstellationLabel] {
        guard !p.x.isEmpty, p.size.width > 0, p.size.height > 0 else { return [] }
        let ranked = rankLabels(p, tiers: tiers, weights: weights)
        var boxes = BrainLabelBoxes(canvas: p.size)
        let everyStar = p.count <= BrainGraphCanvasLogic.smallGraph
        for i in ranked {
            let selected = tiers[i] == .selected
            if !selected, !everyStar { break }
            let half = selected ? selectionReach(p.radius[i]) + 1 : p.radius[i] * labelClear + 1
            boxes.occupy(CGRect(x: p.x[i] - half, y: p.y[i] - half, width: half * 2, height: half * 2))
        }
        let quota = labelQuota(p.size)
        var out: [ConstellationLabel] = []
        for i in ranked where out.count < quota {
            let selected = tiers[i] == .selected
            let reach = (selected ? selectionReach(p.radius[i]) : p.radius[i] * labelClear) + 2
            let size = textSize(texts[i])
            let spots = BrainGraphCanvasLogic.labelSpots(centre: p.point(i), radius: reach, text: size)
            guard let spot = boxes.place(spots, canvas: p.size, force: selected) else { continue }
            out.append(ConstellationLabel(star: i, text: texts[i], rect: spot.rect, selected: selected))
        }
        return out
    }

    // MARK: Camera

    /// Whether the camera is still the automatic fit after `event`. A fresh
    /// graph returns to it; a real orbit or zoom, or an explicit centre,
    /// leaves it; a press alone, the renderer's own moves and the idle turn do not.
    static func nextCameraAutoView(_ autoView: Bool, _ event: ConstellationCameraEvent) -> Bool {
        switch event {
        case .freshGraph: true
        case .userOrbit, .userZoom, .centreOn: false
        case .press, .programmatic, .idleTurn: autoView
        }
    }

    /// Where to aim and how far back to stand to frame the stars: a robust
    /// centroid (the mean of the points within the `share` percentile of
    /// distance from the plain mean), and the distance that fits the
    /// `share`-percentile radius around it, times `frameMargin`, into the
    /// narrower of the camera's two angles. The caller clamps the distance.
    static func frameCloud(
        _ points: [SIMD3<Float>], fieldOfView: Float = fieldOfView, aspect: Double, share: Double = frameShare
    ) -> (centre: SIMD3<Float>, distance: Float) {
        let n = Double(max(1, points.count))
        var c = SIMD3<Double>.zero
        for p in points { c += SIMD3<Double>(p) / n }
        // Distances are kept at Float precision, as the web keeps them in a
        // Float32Array: points mirrored about the centre then tie exactly and
        // the cut keeps or drops both, so a symmetric cloud stays centred.
        func distances(from c: SIMD3<Double>) -> [Double] {
            points.map { Double(Float(simd_length(SIMD3<Double>($0) - c))) }
        }
        func percentile(_ values: [Double]) -> Double {
            guard !values.isEmpty else { return 0 }
            let s = values.sorted()
            return s[max(0, Int((Double(s.count) * share).rounded(.up)) - 1)]
        }
        let d = distances(from: c)
        let cut = percentile(d)
        // One trimming pass: re-centre on the points inside the cut.
        var r = SIMD3<Double>.zero
        var k = 0.0
        for (i, p) in points.enumerated() where d[i] <= cut {
            r += SIMD3<Double>(p)
            k += 1
        }
        if k > 0 { c = r / k }
        let radius = percentile(distances(from: c))
        let vHalf = Double(fieldOfView) * .pi / 360
        let hHalf = atan(tan(vHalf) * max(1e-3, aspect))
        return (SIMD3<Float>(c), Float(radius * frameMargin / sin(min(vHalf, hHalf))))
    }

    /// How far an automatic fit stands, and how far the user may then zoom
    /// out: `maxDistance`, or the fit's own distance when that is farther.
    static func automaticFit(_ distance: Float) -> (distance: Float, maxDistance: Float) {
        let d = min(maxFitDistance, max(minFitDistance, distance))
        return (d, max(maxDistance, d))
    }

    static func easeInOutCubic(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// The view is one VoiceOver element; the list is the way to browse.
    static func accessibilityLabel(itemCount: Int) -> String {
        "Constellation of \(itemCount) notes and memories. Use the list to browse."
    }
}

// MARK: - Idle turn

/// The slow turn of an untouched sky. It runs only with nothing selected, the
/// tab visible, Reduce Motion off and no finger down, after 5 s without a
/// touch; steps at most 30 times a second; and stops for good (until the next
/// touch) after 90 s.
nonisolated enum ConstellationIdleTurn {
    static let idleDelay: Duration = .seconds(5)
    /// One step per thirtieth of a second at most.
    static let maxStepsPerSecond = 30
    static let stepInterval: Duration = .microseconds(1_000_000 / maxStepsPerSecond + 1)
    static let maxTurn: Duration = .seconds(90)
    /// One revolution per three minutes.
    static let radiansPerSecond: Double = 2 * .pi / 180
    /// While turning, labels are re-chosen this often.
    static let rerankInterval: Duration = .seconds(2)

    nonisolated struct State: Equatable, Sendable {
        var selected: Int
        var idle: Duration
        var visible: Bool
        var reduceMotion: Bool
        var pressing: Bool
    }

    static func allowed(_ s: State) -> Bool {
        s.selected == 0 && s.idle >= idleDelay && s.visible && !s.reduceMotion && !s.pressing
    }

    /// Whether a turn that has run for `turned` may take another step.
    static func continues(turned: Duration, max: Duration = maxTurn) -> Bool {
        turned < max
    }

    /// How far a step after `elapsed` turns.
    static func angle(after elapsed: Duration) -> Double {
        let c = elapsed.components
        return radiansPerSecond * (Double(c.seconds) + Double(c.attoseconds) / 1e18)
    }
}
