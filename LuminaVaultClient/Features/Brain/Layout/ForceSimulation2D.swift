// The maths of the 2D Brain layout: a pure, synchronous, deterministic force
// simulation with the web renderer's forces (`render-2d.ts`, d3-force): link
// springs, many-body repulsion capped at 400 pt, weak centring and collision
// at radius + 2. `GraphLayout2D` runs it off the main actor.
//
// Units are points in an unbounded world centred on the origin; the canvas
// owns scale and offset. Nodes are held sorted by id, so the same graph gives
// the same picture whatever order it arrives in. Nothing here reads a clock or
// a random number generator: seeds and jitter come from the id hash.
//
// Cost: repulsion runs over a uniform grid rebuilt every tick into reused
// buffers. A point meets the points of its own and the eight surrounding cells
// one by one (sampling a crowded cell deterministically, so one giant hub
// cannot make it quadratic); every farther cell inside the cap acts as one
// body at its centroid, evaluated once per cell. Nothing allocates per tick
// once the buffers have grown to the graph.

import CoreGraphics
import Foundation
import LuminaVaultShared

nonisolated struct ForceSimulation2D: Sendable {
    nonisolated struct SimNode: Sendable, Equatable {
        var id: String
        var radius: CGFloat
        /// Carried for callers; the forces treat hubs like any point, as on web.
        var isHub: Bool
    }

    nonisolated struct SimLink: Sendable, Equatable {
        /// Indices into the id-sorted nodes. `from` is the edge's source (the
        /// item, for a hub edge), which matters for how the spring splits.
        var from: Int
        var to: Int
        var distance: CGFloat
    }

    // MARK: Constants (web `render-2d.ts` and d3-force defaults)

    /// Below this the layout counts as settled and ticking stops.
    static let settleAlpha: CGFloat = 0.02
    /// How hot a changed node set, or a pin, makes the layout.
    static let reheatAlpha: CGFloat = 0.3
    /// d3's default: alpha falls from 1 to 0.001 in 300 ticks.
    static let alphaDecay: CGFloat = 1 - pow(0.001, 1.0 / 300)
    /// d3's `velocityDecay(0.4)`: a point keeps 60% of its velocity per tick.
    static let velocityRetain: CGFloat = 0.6
    static let chargeStrength: CGFloat = -60
    static let chargeReach: CGFloat = 400
    static let centringStrength: CGFloat = 0.04
    static let collisionPadding: CGFloat = 2
    /// Largest radius `nodeRadius` returns.
    static let maxRadius: CGFloat = 12
    /// Grid cell side. Must exceed twice the largest padded radius, so every
    /// collision partner is in the surrounding cells.
    static let cellSize: CGFloat = 50
    /// A graph spread wider than this many cells gets bigger cells instead.
    static let maxCellsPerSide = 128
    /// A neighbouring cell with more points than this is sampled. A 50 pt
    /// cell holds about 20 non-overlapping smallest points, so collision is
    /// exact whenever the layout is near rest.
    static let cellSampleLimit = 24

    static func nodeRadius(weight: Int, isHub: Bool) -> CGFloat {
        let root = CGFloat(max(0, weight)).squareRoot()
        return isHub ? 3 + min(6, root) : 4 + min(8, root * 1.6)
    }

    static func linkDistance(_ kind: BrainLinkKindDTO) -> CGFloat {
        switch kind {
        case .link, .source: 60
        case .tag, .author, .entity, .space: 40
        case .similar: 90
        }
    }

    /// The simulation's input for a visible graph: nodes sorted by id, links
    /// as index pairs sorted too, self-links and links to unknown ids dropped.
    static func input(for graph: VisibleBrainGraph) -> (nodes: [SimNode], links: [SimLink]) {
        var sorted = graph.nodes.sorted { $0.id < $1.id }
        sorted.removeDuplicates(by: \.id)
        let nodes = sorted.map { node in
            let hub = BrainGraphModel.isHub(node)
            return SimNode(id: node.id, radius: nodeRadius(weight: node.weight, isHub: hub), isHub: hub)
        }
        var index: [String: Int] = [:]
        index.reserveCapacity(nodes.count)
        for (i, node) in nodes.enumerated() { index[node.id] = i }
        var links: [SimLink] = []
        links.reserveCapacity(graph.edges.count)
        for edge in graph.edges where edge.from != edge.to {
            guard let a = index[edge.from], let b = index[edge.to] else { continue }
            links.append(SimLink(from: a, to: b, distance: linkDistance(edge.kind)))
        }
        links.sort { ($0.from, $0.to, $0.distance) < ($1.from, $1.to, $1.distance) }
        return (nodes, links)
    }

    /// Where a point new to a shown graph starts (web `startPosition`): the
    /// mean of its `count` placed neighbours a little apart from them, or near
    /// the centre when it has none, offset by the id hash.
    static func startPosition(id: String, sum: CGPoint, count: Int) -> CGPoint {
        let spread: CGFloat = count > 0 ? 8 : 30
        let hash = BrainIDHash.hashID(id)
        let n = CGFloat(max(1, count))
        return CGPoint(
            x: (count > 0 ? sum.x / n : 0) + BrainIDHash.jitter(hash: hash, axis: 0) * spread,
            y: (count > 0 ? sum.y / n : 0) + BrainIDHash.jitter(hash: hash, axis: 1) * spread
        )
    }

    /// d3's phyllotaxis seed for point `index` of a fresh graph.
    static func spiralPosition(_ index: Int) -> CGPoint {
        let radius = 10 * (0.5 + CGFloat(index)).squareRoot()
        let angle = CGFloat(index) * CGFloat.pi * (3 - CGFloat(5).squareRoot())
        return CGPoint(x: radius * cos(angle), y: radius * sin(angle))
    }

    // MARK: State

    private(set) var nodes: [SimNode] = []
    private(set) var links: [SimLink] = []
    /// Aligned with `nodes`.
    private(set) var positions: [CGPoint] = []
    private(set) var alpha: CGFloat = 0

    private var velocities: [CGPoint] = []
    private var indexByID: [String: Int] = [:]
    /// Where hidden points were, so showing them again restores the picture.
    private var parked: [String: CGPoint] = [:]
    private var pins: [String: CGPoint] = [:]
    private var pinned: [(index: Int, at: CGPoint)] = []
    private var linkStrength: [CGFloat] = []
    private var linkBias: [CGFloat] = []
    private var collisionRadius: [CGFloat] = []
    /// Rotates which members of a crowded cell are sampled.
    private var tickCount = 0
    private var grid = Grid()

    init() {}

    // MARK: Graph

    /// The index of a shown id in `nodes` and `positions`.
    func index(of id: String) -> Int? { indexByID[id] }

    /// Whether these ids make a fresh graph, laid out from scratch: none of
    /// them is shown or parked. An empty graph is never fresh, or it would
    /// forget every remembered position.
    func isFresh(_ ids: some Sequence<String>) -> Bool {
        var any = false
        for id in ids {
            if indexByID[id] != nil || parked[id] != nil { return false }
            any = true
        }
        return any
    }

    /// Builds the input from a visible graph and decides freshness.
    mutating func setGraph(_ graph: VisibleBrainGraph) {
        let input = Self.input(for: graph)
        setGraph(nodes: input.nodes, links: input.links, fresh: isFresh(input.nodes.lazy.map(\.id)))
    }

    /// Replaces the graph. `nodes` must be sorted by id and `links` must index
    /// into them (`input(for:)` builds both). Known ids keep their position
    /// and lose their velocity; hidden ids are parked and restored when they
    /// return; a fresh graph forgets parked positions, seeds newcomers on a
    /// spiral and starts at alpha 1. Otherwise newcomers start near their
    /// placed neighbours and a changed graph reheats to 0.3. The same nodes
    /// and links change nothing and do not reheat.
    mutating func setGraph(nodes newNodes: [SimNode], links newLinks: [SimLink], fresh: Bool) {
        if !fresh, newNodes == nodes, newLinks == links { return }
        let count = newNodes.count

        var nextIndex: [String: Int] = [:]
        nextIndex.reserveCapacity(count)
        for (i, node) in newNodes.enumerated() { nextIndex[node.id] = i }

        if fresh { parked.removeAll() }
        for (i, node) in nodes.enumerated() where nextIndex[node.id] == nil {
            parked[node.id] = positions[i]
        }

        var nextPositions = [CGPoint](repeating: .zero, count: count)
        var placed = [Bool](repeating: false, count: count)
        for (i, node) in newNodes.enumerated() {
            if let old = indexByID[node.id] {
                nextPositions[i] = positions[old]
                placed[i] = true
            } else if let spot = parked.removeValue(forKey: node.id) {
                nextPositions[i] = spot
                placed[i] = true
            }
        }

        var degree = [Int](repeating: 0, count: count)
        for link in newLinks {
            degree[link.from] += 1
            degree[link.to] += 1
        }

        if fresh {
            for i in 0 ..< count where !placed[i] { nextPositions[i] = Self.spiralPosition(i) }
        } else if placed.contains(false) {
            Self.placeNewcomers(&nextPositions, placed: &placed, nodes: newNodes, links: newLinks, degree: degree)
        }

        linkStrength = newLinks.map { 1 / CGFloat(min(degree[$0.from], degree[$0.to])) }
        linkBias = newLinks.map { CGFloat(degree[$0.from]) / CGFloat(degree[$0.from] + degree[$0.to]) }
        collisionRadius = newNodes.map { $0.radius + Self.collisionPadding }

        nodes = newNodes
        links = newLinks
        indexByID = nextIndex
        positions = nextPositions
        velocities = [CGPoint](repeating: .zero, count: count)
        pins = pins.filter { nextIndex[$0.key] != nil }
        rebuildPins()
        alpha = max(alpha, fresh ? 1 : Self.reheatAlpha)
    }

    /// Fixes point `index` at `at` (it is placed there now), or releases it
    /// with `nil`. Fixing reheats to 0.3, so dragging keeps the layout moving
    /// around the point; holding still lets it settle. Releasing does not.
    mutating func pin(_ index: Int, at point: CGPoint?) {
        guard nodes.indices.contains(index) else { return }
        let id = nodes[index].id
        if let point {
            pins[id] = point
            positions[index] = point
            velocities[index] = .zero
            alpha = max(alpha, Self.reheatAlpha)
        } else {
            pins[id] = nil
        }
        rebuildPins()
    }

    private mutating func rebuildPins() {
        pinned = pins.compactMap { id, at in indexByID[id].map { (index: $0, at: at) } }
        pinned.sort { $0.index < $1.index }
    }

    /// Mean of each newcomer's already placed neighbours (newcomers placed
    /// earlier in id order count), as the web places them.
    private static func placeNewcomers(
        _ positions: inout [CGPoint], placed: inout [Bool],
        nodes: [SimNode], links: [SimLink], degree: [Int]
    ) {
        let count = nodes.count
        var start = [Int](repeating: 0, count: count + 1)
        for i in 0 ..< count { start[i + 1] = start[i] + degree[i] }
        var cursor = Array(start.dropLast())
        var neighbours = [Int](repeating: 0, count: start[count])
        for link in links {
            neighbours[cursor[link.from]] = link.to
            cursor[link.from] += 1
            neighbours[cursor[link.to]] = link.from
            cursor[link.to] += 1
        }
        var seen = [Int](repeating: -1, count: count)
        for i in 0 ..< count where !placed[i] {
            var sum = CGPoint.zero
            var n = 0
            for k in start[i] ..< start[i + 1] {
                let j = neighbours[k]
                guard placed[j], seen[j] != i else { continue }
                seen[j] = i
                sum.x += positions[j].x
                sum.y += positions[j].y
                n += 1
            }
            positions[i] = startPosition(id: nodes[i].id, sum: sum, count: n)
            placed[i] = true
        }
    }

    // MARK: Tick

    /// One step, as d3's `tick`: cool, apply link, charge, centring and
    /// collision forces, then move. Returns false once settled (alpha below
    /// `settleAlpha`), and does nothing when already settled.
    mutating func tick() -> Bool {
        let count = positions.count
        guard count > 0, alpha >= Self.settleAlpha else { return false }
        alpha -= alpha * Self.alphaDecay
        tickCount &+= 1

        // Work on locals so the hot loops see uniquely referenced buffers. The
        // forces read `pos` and only then is it moved in place; it is copied
        // only when a published snapshot still shares it.
        var pos = positions
        positions = []
        var vel = velocities
        velocities = []
        var grid = self.grid
        self.grid = Grid()

        applyLinks(pos: pos, vel: &vel, alpha: alpha)
        grid.build(pos)
        grid.applyCharge(pos: pos, vel: &vel, alpha: alpha, tick: tickCount)
        let centring = Self.centringStrength * alpha
        for i in 0 ..< count {
            vel[i].x -= pos[i].x * centring
            vel[i].y -= pos[i].y * centring
        }
        grid.applyCollision(pos: pos, vel: &vel, radius: collisionRadius, tick: tickCount)

        for i in 0 ..< count {
            let v = CGPoint(x: vel[i].x * Self.velocityRetain, y: vel[i].y * Self.velocityRetain)
            vel[i] = v
            pos[i].x += v.x
            pos[i].y += v.y
        }
        for pin in pinned {
            pos[pin.index] = pin.at
            vel[pin.index] = .zero
        }

        positions = pos
        velocities = vel
        self.grid = grid
        return alpha >= Self.settleAlpha
    }

    /// d3 `forceLink`, one iteration: springs on predicted positions, split
    /// by degree so a hub with many members barely moves.
    private func applyLinks(pos: [CGPoint], vel: inout [CGPoint], alpha: CGFloat) {
        let links = links, strength = linkStrength, bias = linkBias
        for k in links.indices {
            let s = links[k].from, t = links[k].to
            var x = pos[t].x + vel[t].x - pos[s].x - vel[s].x
            var y = pos[t].y + vel[t].y - pos[s].y - vel[s].y
            if x == 0, y == 0 {
                let u = Grid.jiggle(s, t)
                x = u.x
                y = u.y
            }
            let length = (x * x + y * y).squareRoot()
            let pull = (length - links[k].distance) / length * alpha * strength[k]
            x *= pull
            y *= pull
            let b = bias[k]
            vel[t].x -= x * b
            vel[t].y -= y * b
            vel[s].x += x * (1 - b)
            vel[s].y += y * (1 - b)
        }
    }
}

// MARK: - Grid

private extension ForceSimulation2D {
    /// Reused scratch for the spatial grid. Arrays only grow; each tick uses a
    /// prefix of them.
    nonisolated struct Grid: Sendable {
        var cellOfPoint: [Int32] = []
        /// Points sorted by cell; cell `c` holds `members[start[c] ..< start[c + 1]]`.
        var members: [Int32] = []
        var start: [Int32] = []
        var centreX: [CGFloat] = []
        var centreY: [CGFloat] = []
        var farX: [CGFloat] = []
        var farY: [CGFloat] = []
        var occupied: [Int32] = []
        var predicted: [CGPoint] = []
        var width = 0
        var height = 0
        var size: CGFloat = ForceSimulation2D.cellSize
        var originX: CGFloat = 0
        var originY: CGFloat = 0

        /// A deterministic tiny offset for two coincident points, opposite for
        /// each of the pair, standing in for d3's random jiggle.
        static func jiggle(_ i: Int, _ j: Int) -> CGPoint {
            let lo = UInt32(truncatingIfNeeded: min(i, j)), hi = UInt32(truncatingIfNeeded: max(i, j))
            let angle = BrainIDHash.jitter(hash: BrainIDHash.mix32(lo &* 0x9E37_79B9 ^ hi), axis: 0) * 2 * .pi
            let sign: CGFloat = i < j ? 1 : -1
            return CGPoint(x: cos(angle) * 1e-6 * sign, y: sin(angle) * 1e-6 * sign)
        }

        private static func grow<T>(_ array: inout [T], to count: Int, with value: T) {
            if array.count < count { array.append(contentsOf: repeatElement(value, count: count - array.count)) }
        }

        mutating func build(_ pos: [CGPoint]) {
            let count = pos.count
            var minX = CGFloat.infinity, minY = CGFloat.infinity
            var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
            for p in pos {
                minX = min(minX, p.x)
                maxX = max(maxX, p.x)
                minY = min(minY, p.y)
                maxY = max(maxY, p.y)
            }
            let limit = CGFloat(ForceSimulation2D.maxCellsPerSide - 1)
            size = max(ForceSimulation2D.cellSize, (maxX - minX) / limit, (maxY - minY) / limit)
            if !size.isFinite { size = ForceSimulation2D.cellSize }
            originX = minX.isFinite ? minX : 0
            originY = minY.isFinite ? minY : 0
            width = min(ForceSimulation2D.maxCellsPerSide, Int((maxX - minX) / size) + 1)
            height = min(ForceSimulation2D.maxCellsPerSide, Int((maxY - minY) / size) + 1)
            let cells = width * height

            Self.grow(&cellOfPoint, to: count, with: 0)
            Self.grow(&members, to: count, with: 0)
            Self.grow(&predicted, to: count, with: .zero)
            Self.grow(&start, to: cells + 1, with: 0)
            Self.grow(&centreX, to: cells, with: 0)
            Self.grow(&centreY, to: cells, with: 0)
            Self.grow(&farX, to: cells, with: 0)
            Self.grow(&farY, to: cells, with: 0)
            for c in 0 ... cells { start[c] = 0 }
            for c in 0 ..< cells {
                centreX[c] = 0
                centreY[c] = 0
            }

            // Counting sort of points into cells, keeping index order within a cell.
            let w = width, h = height, s = size, ox = originX, oy = originY
            for i in 0 ..< count {
                let p = pos[i]
                let cx = min(w - 1, max(0, Int((p.x - ox) / s)))
                let cy = min(h - 1, max(0, Int((p.y - oy) / s)))
                let c = cx + cy * w
                cellOfPoint[i] = Int32(c)
                start[c] += 1
                centreX[c] += p.x
                centreY[c] += p.y
            }
            occupied.removeAll(keepingCapacity: true)
            var running: Int32 = 0
            for c in 0 ..< cells {
                let n = start[c]
                if n > 0 {
                    occupied.append(Int32(c))
                    centreX[c] /= CGFloat(n)
                    centreY[c] /= CGFloat(n)
                }
                running += n
                start[c] = running
            }
            start[cells] = running
            for i in stride(from: count - 1, through: 0, by: -1) {
                let c = Int(cellOfPoint[i])
                start[c] -= 1
                members[Int(start[c])] = Int32(i)
            }
        }

        /// Many-body repulsion, d3's `forceManyBody().strength(-60).distanceMax(400)`.
        mutating func applyCharge(pos: [CGPoint], vel: inout [CGPoint], alpha: CGFloat, tick: Int) {
            let w = width, h = height
            let reach2 = ForceSimulation2D.chargeReach * ForceSimulation2D.chargeReach
            let strength = ForceSimulation2D.chargeStrength
            let span = Int((ForceSimulation2D.chargeReach / size).rounded(.up))

            // Far field: each occupied cell feels every occupied cell beyond its
            // neighbours and inside the cap as one body at that cell's centroid.
            for a in occupied {
                let a = Int(a)
                let ax = a % w, ay = a / w
                let cx = centreX[a], cy = centreY[a]
                var fx: CGFloat = 0, fy: CGFloat = 0
                for by in max(0, ay - span) ... min(h - 1, ay + span) {
                    let row = by * w
                    let nearRow = abs(by - ay) <= 1
                    for bx in max(0, ax - span) ... min(w - 1, ax + span) {
                        if nearRow, abs(bx - ax) <= 1 { continue }
                        let b = row + bx
                        let n = start[b + 1] - start[b]
                        if n == 0 { continue }
                        let dx = centreX[b] - cx, dy = centreY[b] - cy
                        let d2 = dx * dx + dy * dy
                        if d2 >= reach2 { continue }
                        let weight = CGFloat(n) / max(d2, 1)
                        fx += dx * weight
                        fy += dy * weight
                    }
                }
                farX[a] = fx * strength
                farY[a] = fy * strength
            }

            // Near field: point by point over the surrounding cells.
            let limit = ForceSimulation2D.cellSampleLimit
            for i in pos.indices {
                let c = Int(cellOfPoint[i])
                let px = pos[i].x, py = pos[i].y
                var vx = farX[c] * alpha, vy = farY[c] * alpha
                let cx = c % w, cy = c / w
                for by in max(0, cy - 1) ... min(h - 1, cy + 1) {
                    for bx in max(0, cx - 1) ... min(w - 1, cx + 1) {
                        let b = bx + by * w
                        let lo = Int(start[b]), hi = Int(start[b + 1])
                        let n = hi - lo
                        if n == 0 { continue }
                        var step = 1, first = lo
                        var weight: CGFloat = 1
                        if n > limit {
                            step = (n + limit - 1) / limit
                            first = lo + (tick &+ i) % step
                            weight = CGFloat(n) / CGFloat((hi - first + step - 1) / step)
                        }
                        let scale = strength * alpha * weight
                        var k = first
                        while k < hi {
                            let j = Int(members[k])
                            k += step
                            if j == i { continue }
                            var dx = pos[j].x - px, dy = pos[j].y - py
                            var d2 = dx * dx + dy * dy
                            if d2 >= reach2 { continue }
                            if d2 == 0 {
                                let u = Self.jiggle(i, j)
                                dx = u.x
                                dy = u.y
                                d2 = dx * dx + dy * dy
                            }
                            // d3's distanceMin(1): softens the force inside 1 pt.
                            let l = d2 < 1 ? d2.squareRoot() : d2
                            vx += dx * scale / l
                            vy += dy * scale / l
                        }
                    }
                }
                vel[i].x += vx
                vel[i].y += vy
            }
        }

        /// d3 `forceCollide(r + 2)`, one iteration, on predicted positions. Each
        /// point takes its own share of every overlap, so a pair separates by
        /// the full overlap as in d3.
        mutating func applyCollision(pos: [CGPoint], vel: inout [CGPoint], radius: [CGFloat], tick: Int) {
            let count = pos.count
            for i in 0 ..< count {
                predicted[i] = CGPoint(x: pos[i].x + vel[i].x, y: pos[i].y + vel[i].y)
            }
            let w = width, h = height
            let limit = ForceSimulation2D.cellSampleLimit
            for i in 0 ..< count {
                let c = Int(cellOfPoint[i])
                let qx = predicted[i].x, qy = predicted[i].y
                let ri = radius[i], ri2 = ri * ri
                var vx: CGFloat = 0, vy: CGFloat = 0
                let cx = c % w, cy = c / w
                for by in max(0, cy - 1) ... min(h - 1, cy + 1) {
                    for bx in max(0, cx - 1) ... min(w - 1, cx + 1) {
                        let b = bx + by * w
                        let lo = Int(start[b]), hi = Int(start[b + 1])
                        let n = hi - lo
                        if n == 0 { continue }
                        let step = n > limit ? (n + limit - 1) / limit : 1
                        var k = n > limit ? lo + (tick &+ i) % step : lo
                        while k < hi {
                            let j = Int(members[k])
                            k += step
                            if j == i { continue }
                            let rj = radius[j]
                            let r = ri + rj
                            var dx = qx - predicted[j].x, dy = qy - predicted[j].y
                            var l = dx * dx + dy * dy
                            if l >= r * r { continue }
                            if l == 0 {
                                let u = Self.jiggle(j, i)
                                dx = u.x
                                dy = u.y
                                l = dx * dx + dy * dy
                            }
                            l = l.squareRoot()
                            let push = (r - l) / l * (rj * rj / (ri2 + rj * rj))
                            vx += dx * push
                            vy += dy * push
                        }
                    }
                }
                vel[i].x += vx
                vel[i].y += vy
            }
        }
    }
}

private extension Array {
    /// Drops elements whose key equals the previous element's (input is sorted).
    nonisolated mutating func removeDuplicates(by key: (Element) -> String) {
        guard count > 1 else { return }
        var kept = 1
        for i in 1 ..< count where key(self[i]) != key(self[kept - 1]) {
            self[kept] = self[i]
            kept += 1
        }
        removeLast(count - kept)
    }
}
