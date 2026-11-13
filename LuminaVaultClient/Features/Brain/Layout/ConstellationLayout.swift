// Pure: where every point sits in the 3D Constellation. A port of the web
// app's `constellation-layout.ts` at its final state, with the same numbers.
// No RealityKit here: the renderer only copies the positions into entities.
//
// `layoutConstellation` lays out one graph. A `ConstellationLayout` value is
// the renderer's memory of where every star is (the web `ConstellationMemory`),
// so the sky holds still while filters change: `layout(_:)` keeps every known
// id where it was and places only newcomers among them, unless fewer than half
// of the visible ids are known, when it starts again from scratch (`fresh`).
//
// Deterministic and independent of node and edge order: nodes are taken in id
// order (UTF-16 code units, as JavaScript compares), every hashed placement
// comes from `BrainIDHash`, and the link force's jiggle from a fixed seed.
// Runs off the main actor: see `ConstellationLayoutRunner`.

import Foundation
import LuminaVaultShared

nonisolated struct ConstellationLayout: Sendable {
    typealias Vec = SIMD3<Double>

    // MARK: Constants (web names in comments where they differ)

    /// Memories with a server position are scaled so the bulk of them (the
    /// 95th percentile of distances from the origin) spans this radius; any
    /// farther memory is pulled in to it. A fresh layout is scaled so 95% of
    /// its points lie within it.
    static let cloudRadius: Double = 100
    static let cloudPercentile = 0.95
    /// Share of positioned memories whose extent sets the scale (nearest rank).
    static let scalePercentile = 0.95
    /// Tick budget for a fresh layout of up to `fullTicksUpTo` free points.
    static let fullTicks = 300
    static let fullTicksUpTo = 500
    /// Fewest ticks a large fresh layout gets.
    static let minTicks = 80
    /// Ticks when only newcomers move among fixed points: 30 plus 2 each, at most 80.
    static let incrementalTicks = 80
    static let incrementalTicksMin = 30
    static let incrementalTicksEach = 2
    static let alphaMin = 0.001
    /// d3's velocity decay: the share of its velocity a point keeps per tick.
    static let velocityKeep = 0.6
    /// Pull of every free point toward the origin.
    static let centring = 0.03
    /// Repulsion reaches this many link lengths.
    static let repulsionReach = 2.0
    /// Repulsion strength at a link length of 30; scaled with the square of the spacing.
    static let repulsion = -750.0
    /// Pairs nearer than this many link lengths push as if this far apart.
    static let repulsionFloor = 0.1
    /// Most points of one grid cell that push on a point in a tick; a fuller
    /// cell is sampled evenly and each sampled push counts k times.
    static let cellSample = 12
    /// A run ends once no free point moves farther than this share of a link length in a tick.
    static let settled = 1e-3
    /// A parent with c unplaced neighbours starts them in a ball of about
    /// `childSpread` × cbrt(c) link lengths.
    static let childSpread = 0.6
    /// Farthest a newcomer may end up, in cloud radii.
    static let strayLimit = 1.5

    // MARK: Result

    /// What one `layoutConstellation` call cost (web `layoutCounters`):
    /// repulsion pair visits summed over every tick, ticks run, and bodies
    /// simulated (free points).
    struct Cost: Equatable, Sendable {
        var pairVisits = 0
        var ticks = 0
        var bodies = 0
    }

    struct Result: Sendable {
        var positions: [String: Vec]
        /// Factor from server `pos` to world units actually used, or nil if none was needed.
        var scale: Double?
        /// Link length in world units, for laying out newcomers later at the same density.
        var spacing: Double
        /// Whether the layout was normalised (no prior: a fresh layout).
        var normalised: Bool
        var cost: Cost
    }

    // MARK: Memory

    private var known: [String: Vec] = [:]
    private var scale: Double?
    private var spacing: Double?

    /// Whether the last layout started from scratch (fewer than half of its
    /// ids were known): every position may have changed, and the renderer
    /// frames it afresh.
    private(set) var fresh = false
    /// Whether the last layout placed any id it had not seen before.
    private(set) var grew = false

    init() {}

    /// The renderer's entry point: `place(_:)` as Float, with `fresh`.
    mutating func layout(_ graph: VisibleBrainGraph) -> (positions: [String: SIMD3<Float>], fresh: Bool) {
        let exact = place(graph)
        return (exact.mapValues { SIMD3<Float>($0) }, fresh)
    }

    /// Positions for every visible id (web `ConstellationMemory.layout`).
    mutating func place(_ graph: VisibleBrainGraph) -> [String: Vec] {
        var knownCount = 0
        for n in graph.nodes where known[n.id] != nil { knownCount += 1 }
        let n = graph.nodes.count
        let allKnown = knownCount == n
        fresh = knownCount * 2 < n
        grew = !allKnown
        if allKnown {
            var out: [String: Vec] = [:]
            out.reserveCapacity(n)
            for node in graph.nodes { out[node.id] = known[node.id] }
            return out
        }
        if fresh {
            // Laid out among a few known stars at their old scale, a much
            // larger graph would overflow the cloud several times over: start
            // again, normalised.
            known.removeAll(keepingCapacity: true)
            let result = Self.layoutConstellation(graph)
            scale = result.scale
            spacing = result.spacing
            known.merge(result.positions) { _, new in new }
            return result.positions
        }
        if scale == nil { scale = Self.memoryScale(graph.nodes) }
        let result = Self.layoutConstellation(graph, prior: known, scale: scale, spacing: spacing)
        known.merge(result.positions) { _, new in new }
        return result.positions
    }

    // MARK: Pure helpers

    /// A stable value in [-1, 1) per id and axis.
    static func unit(_ id: String, _ axis: UInt32) -> Double {
        BrainIDHash.jitter(id, axis: axis) * 2
    }

    /// Whether `a` sorts before `b` by UTF-16 code units, as JavaScript compares strings.
    static func idPrecedes(_ a: String, _ b: String) -> Bool {
        a.utf16.lexicographicallyPrecedes(b.utf16)
    }

    /// Length of a vector without overflow or underflow on the way (`Math.hypot`).
    static func length(_ x: Double, _ y: Double, _ z: Double) -> Double {
        hypot(hypot(x, y), z)
    }

    private static func hasPosition(_ n: BrainGraphNodeDTO) -> Bool {
        guard n.kind == .memory, let p = n.pos else { return false }
        return p.x.isFinite && p.y.isFinite && p.z.isFinite
    }

    /// The factor that maps server positions into the cloud: `cloudRadius`
    /// over the 95th-percentile distance of the positioned memories from the
    /// origin, so one far memory does not crush the rest. Nil when no memory
    /// has a usable position, or when they all sit (almost) at the origin.
    static func memoryScale(_ nodes: [BrainGraphNodeDTO]) -> Double? {
        var extents: [Double] = []
        for n in nodes where hasPosition(n) {
            guard let p = n.pos else { continue }
            let d = length(p.x, p.y, p.z)
            if d.isFinite { extents.append(d) }
        }
        guard !extents.isEmpty else { return nil }
        extents.sort()
        let at = max(0, Int((Double(extents.count) * scalePercentile).rounded(.up)) - 1)
        let extent = extents[at]
        let scale = cloudRadius / extent
        return extent > 1e-9 && scale.isFinite ? scale : nil
    }

    /// A memory's server position in the cloud: scaled, and pulled in to `cloudRadius` if beyond.
    private static func placeMemory(_ p: GraphPosition3D, scale: Double) -> Vec {
        let v = Vec(p.x * scale, p.y * scale, p.z * scale)
        let d = length(v.x, v.y, v.z)
        guard d > cloudRadius else { return v }
        return v * (cloudRadius / d)
    }

    /// Link length in world units before normalising: about the spacing of n points in the cloud.
    static func naturalSpacing(_ n: Int) -> Double {
        min(60, max(8, 130 / cbrt(Double(max(1, n)))))
    }

    /// Ticks for a fresh layout of n free points: the full budget up to 500, then fewer.
    static func tickBudget(_ n: Int) -> Int {
        if n <= fullTicksUpTo { return fullTicks }
        return max(minTicks, Int((Double(fullTicks * fullTicksUpTo) / Double(n)).rounded()))
    }

    private static func percentileRadius(_ b: Bodies, share: Double) -> Double {
        guard !b.fixed.isEmpty else { return 0 }
        var r = (0 ..< b.count).map { length(b.x[$0], b.y[$0], b.z[$0]) }
        r.sort()
        return r[max(0, Int((Double(r.count) * share).rounded(.up)) - 1)]
    }

    private static func isHubLink(_ kind: BrainLinkKindDTO) -> Bool {
        switch kind {
        case .tag, .author, .entity, .space: true
        case .link, .source, .similar: false
        }
    }

    // MARK: Layout

    /// Lays out every visible point in 3D.
    ///
    /// Ids in `prior` keep their position and are fixed. Memories with a
    /// server `pos` are fixed at that position times `scale` (by default
    /// `memoryScale` of the visible nodes), pulled in to `cloudRadius` if
    /// beyond. Every other point is free and settles in a deterministic 3D
    /// force layout: links pull (hub edges shorter, `similar` longer), points
    /// repel within a cap, and a weak pull toward the origin keeps separate
    /// groups and unlinked points near the cloud. Ticked in a plain loop, at
    /// most a fixed number of times, stopping early once no point moves, or
    /// when the calling task is cancelled (its result is then discarded).
    ///
    /// Only free points are simulated: fixed points push on them from a grid
    /// built once and pull on them through their links.
    ///
    /// With an empty prior the result is scaled so 95% of points lie within
    /// `cloudRadius`, and `scale` and `spacing` include that factor. A
    /// non-empty prior is never rescaled, and newcomers are pulled in to
    /// `strayLimit` cloud radii.
    static func layoutConstellation(
        _ graph: VisibleBrainGraph,
        prior: [String: Vec] = [:],
        scale: Double? = nil,
        spacing: Double? = nil
    ) -> Result {
        let nodes = graph.nodes.sorted { idPrecedes($0.id, $1.id) }
        let n = nodes.count
        let normalise = prior.isEmpty
        let memScale = scale ?? memoryScale(nodes)
        var space = spacing ?? naturalSpacing(n)

        // Fixed points first: what is already shown, then server positions.
        var at: [String: Int] = [:]
        at.reserveCapacity(n)
        var b = Bodies(count: n)
        var anchored = false
        var freeCount = 0
        for i in 0 ..< n {
            let node = nodes[i]
            at[node.id] = i
            var p = prior[node.id]
            if p != nil {
                anchored = true
            } else if hasPosition(node), let pos = node.pos {
                p = memScale.map { placeMemory(pos, scale: $0) } ?? .zero
            }
            if let p {
                b.x[i] = p.x
                b.y[i] = p.y
                b.z[i] = p.z
                b.fixed[i] = true
            } else {
                freeCount += 1
            }
        }

        var cost = Cost()
        if freeCount > 0 {
            var near = NeighbourLists(nodes: nodes, graph: graph, at: at)
            startingPoints(nodes, near: &near, bodies: &b, space: space, freeCount: freeCount)
            let ticks = anchored
                ? min(incrementalTicks, incrementalTicksMin + incrementalTicksEach * freeCount)
                : tickBudget(freeCount)
            let sp = springs(graph, at: at, fixed: b.fixed, space: space)
            cost = simulate(&b, springs: sp, space: space, ticks: ticks, alpha0: anchored ? 0.6 : 1)
            // Sampled pushes are rough beside a crowd of fixed points; a
            // newcomer they carried off is brought back to the edge of the cloud.
            if !normalise { pullIn(&b, limit: strayLimit * cloudRadius) }
        }

        // A fresh layout is scaled once so the bulk fills the cloud.
        var effectiveScale = memScale
        var normalised = false
        if normalise {
            let r = percentileRadius(b, share: cloudPercentile)
            let f = cloudRadius / r
            if r > 1e-9, f.isFinite {
                for i in 0 ..< n {
                    b.x[i] *= f
                    b.y[i] *= f
                    b.z[i] *= f
                }
                effectiveScale = effectiveScale.map { $0 * f }
                space *= f
                normalised = true
            }
        }

        var out: [String: Vec] = [:]
        out.reserveCapacity(n)
        for i in 0 ..< n { out[nodes[i].id] = Vec(b.x[i], b.y[i], b.z[i]) }
        return Result(positions: out, scale: effectiveScale, spacing: space, normalised: normalised, cost: cost)
    }

    /// Free points farther than `limit` from the origin are moved in to it, along their direction.
    private static func pullIn(_ b: inout Bodies, limit: Double) {
        for i in 0 ..< b.count where !b.fixed[i] {
            let d = length(b.x[i], b.y[i], b.z[i])
            guard d > limit else { continue }
            let k = limit / d
            b.x[i] *= k
            b.y[i] *= k
            b.z[i] *= k
        }
    }

    /// Where the free points start: fixed points stay put; the rest are
    /// reached outward from them (and from each group's heaviest point, when
    /// a group has nothing fixed) in a hashed direction, so the simulation
    /// begins from the graph's own shape. A parent with a few children puts
    /// them one link length away; one with many spreads them through a ball.
    /// Neighbours are visited in id order. Only fixed points next to a free
    /// one are visited.
    private static func startingPoints(
        _ nodes: [BrainGraphNodeDTO], near: inout NeighbourLists, bodies b: inout Bodies, space: Double, freeCount: Int
    ) {
        let n = nodes.count
        var placed = b.fixed
        var queue = [Int](repeating: 0, count: n)
        var tail = 0
        // The fixed points with a free neighbour, in id order: the only ones that place anything.
        var seeds = [Bool](repeating: false, count: n)
        for i in 0 ..< n where !b.fixed[i] {
            for j in near.list(i) where b.fixed[j] { seeds[j] = true }
        }
        for i in 0 ..< n where seeds[i] {
            queue[tail] = i
            tail += 1
        }
        var children: [Int] = []
        let ball = space * cbrt(Double(max(1, freeCount))) * 0.6
        let byWeight = (0 ..< n).sorted {
            nodes[$0].weight != nodes[$1].weight ? nodes[$0].weight > nodes[$1].weight : $0 < $1
        }
        var head = 0
        var root = 0
        while true {
            while head < tail {
                let from = queue[head]
                head += 1
                children.removeAll(keepingCapacity: true)
                for j in near.list(from) where !placed[j] { children.append(j) }
                let crowd = childSpread * cbrt(Double(children.count))
                for j in children {
                    let id = nodes[j].id
                    let dx = unit(id, 0), dy = unit(id, 1), dz = unit(id, 2)
                    let l = length(dx, dy, dz)
                    let len = l == 0 ? 1 : l
                    let r = space * max(1, crowd * cbrt((unit(id, 6) + 1) / 2))
                    b.x[j] = b.x[from] + dx / len * r
                    b.y[j] = b.y[from] + dy / len * r
                    b.z[j] = b.z[from] + dz / len * r
                    placed[j] = true
                    queue[tail] = j
                    tail += 1
                }
            }
            while root < n, placed[byWeight[root]] { root += 1 }
            if root >= n { break }
            let i = byWeight[root]
            let id = nodes[i].id
            b.x[i] = unit(id, 3) * ball
            b.y[i] = unit(id, 4) * ball
            b.z[i] = unit(id, 5) * ball
            placed[i] = true
            queue[tail] = i
            tail += 1
        }
    }

    /// d3's link force: strength 1 / the smaller endpoint degree, the
    /// correction split by degree. Degrees count every visible link; only
    /// links with a free end are kept, in (from, to, kind) id order.
    private static func springs(
        _ graph: VisibleBrainGraph, at: [String: Int], fixed: [Bool], space: Double
    ) -> Springs {
        var degree = [Int](repeating: 0, count: fixed.count)
        var kept: [(s: Int, t: Int, kind: BrainLinkKindDTO)] = []
        for e in graph.edges where e.from != e.to {
            guard let s = at[e.from], let t = at[e.to] else { continue }
            degree[s] += 1
            degree[t] += 1
            if !(fixed[s] && fixed[t]) { kept.append((s, t, e.kind)) }
        }
        // Indices follow id order, so this is the order of (from, to, kind) ids.
        kept.sort {
            if $0.s != $1.s { return $0.s < $1.s }
            if $0.t != $1.t { return $0.t < $1.t }
            return idPrecedes($0.kind.rawValue, $1.kind.rawValue)
        }
        var out = Springs()
        out.source.reserveCapacity(kept.count)
        for (s, t, kind) in kept {
            out.source.append(s)
            out.target.append(t)
            out.length.append(isHubLink(kind) ? space * 0.7 : kind == .similar ? space * 1.4 : space)
            out.strength.append(1 / Double(min(degree[s], degree[t])))
            out.bias.append(Double(degree[s]) / Double(degree[s] + degree[t]))
        }
        return out
    }

    /// Ticks the free points: d3's link force, a short-range repulsion and a
    /// weak pull toward the origin, integrated as d3 does (velocity decay
    /// 0.6). The repulsion follows d3's many-body law, tapers to nothing at
    /// `repulsionReach` link lengths and is floored at `repulsionFloor`. Free
    /// points sit in a grid rebuilt every tick, fixed ones in a grid built
    /// once; each free point is pushed by the points in its own and the
    /// neighbouring cells of both, at most `cellSample` per cell.
    private static func simulate(
        _ b: inout Bodies, springs sp: Springs, space: Double, ticks: Int, alpha0: Double
    ) -> Cost {
        let n = b.count
        let field = Field(b)
        defer { field.release() }
        var free: [Int] = []
        var still: [Int] = []
        for i in 0 ..< n {
            if b.fixed[i] { still.append(i) } else { free.append(i) }
        }
        let nf = free.count

        let reach = space * repulsionReach
        field.reach2 = reach * reach
        field.floor = space * repulsionFloor
        field.floor2 = field.floor * field.floor
        let strength = repulsion * (space / 30) * (space / 30)
        let inv = 1 / reach
        let moving = ConstellationGrid(capacity: nf, inv: inv)
        var standing: ConstellationGrid?
        if !still.isEmpty {
            let grid = ConstellationGrid(capacity: still.count, inv: inv)
            grid.fill(still, field)
            standing = grid
        }
        var random = SeededRandom(seed: 0x5EED)
        let settled2 = (space * settled) * (space * settled)
        let step2 = space * space
        var visits = 0
        let decay = 1 - pow(alphaMin, 1 / Double(ticks))
        var alpha = alpha0
        var tick = 0
        let x = field.x, y = field.y, z = field.z
        let vx = field.vx, vy = field.vy, vz = field.vz

        while tick < ticks {
            if Task.isCancelled { break }
            alpha += -alpha * decay

            // Links, in place as d3 does: each sees the velocities the earlier ones left.
            for e in 0 ..< sp.source.count {
                let s = sp.source[e], t = sp.target[e]
                var dx = x[t] + vx[t] - x[s] - vx[s]
                if dx == 0 || dx.isNaN { dx = random.jiggle() }
                var dy = y[t] + vy[t] - y[s] - vy[s]
                if dy == 0 || dy.isNaN { dy = random.jiggle() }
                var dz = z[t] + vz[t] - z[s] - vz[s]
                if dz == 0 || dz.isNaN { dz = random.jiggle() }
                let l = (dx * dx + dy * dy + dz * dz).squareRoot()
                let k = (l - sp.length[e]) / l * alpha * sp.strength[e]
                dx *= k
                dy *= k
                dz *= k
                let bt = sp.bias[e]
                if !b.fixed[t] {
                    vx[t] -= dx * bt
                    vy[t] -= dy * bt
                    vz[t] -= dz * bt
                }
                if !b.fixed[s] {
                    vx[s] += dx * (1 - bt)
                    vy[s] += dy * (1 - bt)
                    vz[s] += dz * (1 - bt)
                }
            }

            // Repulsion, cell by cell.
            field.w0 = strength * alpha
            field.tick = tick
            moving.fill(free, field)
            for o in 0 ..< moving.occupiedCount {
                visits += repelCell(field, moving: moving, standing: standing, h: moving.occupied[o])
            }

            // Centring, then the step.
            let pull = centring * alpha
            var most = 0.0
            for f in 0 ..< nf {
                let i = free[f]
                vx[i] = (vx[i] - x[i] * pull) * velocityKeep
                vy[i] = (vy[i] - y[i] * pull) * velocityKeep
                vz[i] = (vz[i] - z[i] * pull) * velocityKeep
                var d2 = vx[i] * vx[i] + vy[i] * vy[i] + vz[i] * vz[i]
                if d2 > step2 {
                    // No point moves more than a link length in a tick: a
                    // sampled push counts many times over and can otherwise
                    // fling one away.
                    let k = space / d2.squareRoot()
                    vx[i] *= k
                    vy[i] *= k
                    vz[i] *= k
                    d2 = step2
                }
                x[i] += vx[i]
                y[i] += vy[i]
                z[i] += vz[i]
                if d2 > most { most = d2 }
            }
            tick += 1
            if most < settled2 { break }
        }
        field.copy(into: &b)
        return Cost(pairVisits: visits, ticks: tick, bodies: nf)
    }

    /// Neighbour cell offsets: the cell itself and its 26 neighbours.
    private static let around: [Int] = {
        var out: [Int] = []
        for ox in -1 ... 1 { for oy in -1 ... 1 { for oz in -1 ... 1 { out += [ox, oy, oz] } } }
        return out
    }()

    /// Half of the 26 neighbours, so each pair of cells is met once.
    private static let forward: [Int] = {
        var out: [Int] = []
        for ox in -1 ... 1 {
            for oy in -1 ... 1 {
                for oz in -1 ... 1 where ox > 0 || (ox == 0 && (oy > 0 || (oy == 0 && oz > 0))) {
                    out += [ox, oy, oz]
                }
            }
        }
        return out
    }()

    /// A separation for two points on the same spot: `floor` long at most, in
    /// a direction hashed from the pair, opposite for the two ends.
    private static func part(_ a: Int, _ j: Int, floor: Double) -> Vec {
        let lo = UInt32(truncatingIfNeeded: min(a, j)), hi = UInt32(truncatingIfNeeded: max(a, j))
        let h = BrainIDHash.mix32((lo &* 0x9E37_79B1) ^ hi)
        let sign = a < j ? floor : -floor
        return Vec(
            (Double(h & 0x3FF) / 0x3FF - 0.5) * sign,
            (Double((h >> 10) & 0x3FF) / 0x3FF - 0.5) * sign,
            (Double((h >> 20) & 0x3FF) / 0x3FF - 0.5) * sign
        )
    }

    /// How sparsely `c` candidates are sampled: every one up to `cellSample`, then every k-th.
    private static func every(_ c: Int) -> Int {
        c <= cellSample ? 1 : (c + cellSample - 1) / cellSample
    }

    /// The repulsion on the free points of cell `h`: among themselves and with
    /// the free points of the forward half of the neighbouring cells (each
    /// pair once, both ends pushed), then from the fixed points of all 27
    /// cells around (only the free end pushed). A cell of more than
    /// `cellSample` candidates is met every k-th point, k times over, the
    /// offset turning with the point and the tick. Returns the pairs visited.
    private static func repelCell(_ f: Field, moving: ConstellationGrid, standing: ConstellationGrid?, h: Int) -> Int {
        let x = f.x, y = f.y, z = f.z, vx = f.vx, vy = f.vy, vz = f.vz
        let reach2 = f.reach2, floor = f.floor, floor2 = f.floor2, w0 = f.w0, tick = f.tick
        let items = moving.items
        let cx = moving.cx[h], cy = moving.cy[h], cz = moving.cz[h]
        let sh = moving.start[h]
        let eh = sh + moving.count[h]
        var visits = 0

        /// One pair: the push on `a` (at `p`) from `j`, counted `k` times, or nil beyond reach.
        func push(_ a: Int, _ p: Vec, _ j: Int, _ k: Int) -> Vec? {
            var d = Vec(x[j] - p.x, y[j] - p.y, z[j] - p.z)
            var l2 = d.x * d.x + d.y * d.y + d.z * d.z
            if l2 >= reach2 { return nil }
            let taper = 1 - l2 / reach2
            if l2 < floor2 {
                if l2 < 1e-12 * floor2 { d = part(a, j, floor: floor) }
                l2 = floor2
            }
            return d * (w0 * Double(k) / l2 * taper * taper)
        }

        for o in stride(from: -3, to: forward.count, by: 3) {
            let g = o < 0 ? h : moving.slot(cx + forward[o], cy + forward[o + 1], cz + forward[o + 2], make: false)
            if g < 0 { continue }
            let sg = moving.start[g]
            let eg = sg + moving.count[g]
            for k in sh ..< eh {
                let a = items[k]
                let from = g == h ? k + 1 : sg
                let step = every(eg - from)
                let p = Vec(x[a], y[a], z[a])
                var pv = Vec.zero
                let first = from + (k + tick) % step
                if first < eg { visits += (eg - first + step - 1) / step }
                var m = first
                while m < eg {
                    let j = items[m]
                    m += step
                    guard let d = push(a, p, j, step) else { continue }
                    pv += d
                    vx[j] -= d.x
                    vy[j] -= d.y
                    vz[j] -= d.z
                }
                vx[a] += pv.x
                vy[a] += pv.y
                vz[a] += pv.z
            }
        }
        guard let standing else { return visits }
        let still = standing.items
        for o in stride(from: 0, to: around.count, by: 3) {
            let g = standing.slot(cx + around[o], cy + around[o + 1], cz + around[o + 2], make: false)
            if g < 0 { continue }
            let sg = standing.start[g]
            let eg = sg + standing.count[g]
            let step = every(standing.count[g])
            for k in sh ..< eh {
                let a = items[k]
                let p = Vec(x[a], y[a], z[a])
                var pv = Vec.zero
                let first = sg + (a + tick) % step
                if first < eg { visits += (eg - first + step - 1) / step }
                var m = first
                while m < eg {
                    let j = still[m]
                    m += step
                    guard let d = push(a, p, j, step) else { continue }
                    pv += d
                }
                vx[a] += pv.x
                vy[a] += pv.y
                vz[a] += pv.z
            }
        }
        return visits
    }
}

// MARK: - Scratch

/// Points of a graph by index in id order: positions, and which are fixed.
private nonisolated struct Bodies: Sendable {
    var x: [Double]
    var y: [Double]
    var z: [Double]
    var fixed: [Bool]
    var count: Int { fixed.count }

    init(count: Int) {
        x = [Double](repeating: 0, count: count)
        y = x
        z = x
        fixed = [Bool](repeating: false, count: count)
    }
}

/// Links as parallel arrays, in a stable order.
private nonisolated struct Springs: Sendable {
    var source: [Int] = []
    var target: [Int] = []
    var length: [Double] = []
    var strength: [Double] = []
    /// Share of the correction the target takes (d3's bias); the source takes the rest.
    var bias: [Double] = []
}

/// Each point's visible neighbours other than itself, by index in id order,
/// worked out the first time they are asked for.
private nonisolated struct NeighbourLists {
    private let nodes: [BrainGraphNodeDTO]
    private let graph: VisibleBrainGraph
    private let at: [String: Int]
    private var cache: [[Int]?]

    init(nodes: [BrainGraphNodeDTO], graph: VisibleBrainGraph, at: [String: Int]) {
        self.nodes = nodes
        self.graph = graph
        self.at = at
        cache = Array(repeating: nil, count: nodes.count)
    }

    mutating func list(_ i: Int) -> [Int] {
        if let list = cache[i] { return list }
        var list: [Int] = []
        for other in graph.index.neighbours[nodes[i].id] ?? [] {
            if let j = at[other], j != i { list.append(j) }
        }
        list.sort()
        cache[i] = list
        return list
    }
}

/// What the simulation reads and writes, in raw buffers: the repulsion's
/// inner loop runs millions of times and must not pay for array copies or
/// bounds checks. Owned by one `simulate` call, released by it, and never
/// shared, so it is not `Sendable`.
private nonisolated final class Field {
    let x: UnsafeMutablePointer<Double>
    let y: UnsafeMutablePointer<Double>
    let z: UnsafeMutablePointer<Double>
    let vx: UnsafeMutablePointer<Double>
    let vy: UnsafeMutablePointer<Double>
    let vz: UnsafeMutablePointer<Double>
    let count: Int
    var reach2 = 0.0
    var floor = 0.0
    var floor2 = 0.0
    /// This tick's repulsion strength times alpha, and the tick (sampling offset).
    var w0 = 0.0
    var tick = 0

    init(_ b: Bodies) {
        count = b.count
        let n = max(1, count)
        func buffer(_ values: [Double]?) -> UnsafeMutablePointer<Double> {
            let p = UnsafeMutablePointer<Double>.allocate(capacity: n)
            p.initialize(repeating: 0, count: n)
            if let values { for i in 0 ..< values.count { p[i] = values[i] } }
            return p
        }
        x = buffer(b.x)
        y = buffer(b.y)
        z = buffer(b.z)
        vx = buffer(nil)
        vy = buffer(nil)
        vz = buffer(nil)
    }

    func copy(into b: inout Bodies) {
        for i in 0 ..< count {
            b.x[i] = x[i]
            b.y[i] = y[i]
            b.z[i] = z[i]
        }
    }

    func release() {
        for p in [x, y, z, vx, vy, vz] { p.deallocate() }
    }
}

/// A uniform grid of cells in an open-addressing table: each cell's points
/// sit together in `items`, from `start` for `count`, so a crowded cell can be
/// sampled without walking it. Refilled from scratch for every fill;
/// allocates nothing after creation. Local to one `simulate` call.
private nonisolated final class ConstellationGrid {
    private static let span: Int64 = 4096
    private static let offset: Int64 = 2048

    private var keys: [Int64]
    private let mask: Int
    private let inv: Double
    private(set) var cx: [Int]
    private(set) var cy: [Int]
    private(set) var cz: [Int]
    private(set) var start: [Int]
    private(set) var count: [Int]
    private var cursor: [Int]
    /// Occupied slots, in the order they were first filled.
    private(set) var occupied: [Int]
    private(set) var occupiedCount = 0
    private(set) var items: [Int]
    private var slotOf: [Int]

    init(capacity: Int, inv: Double) {
        var cap = 16
        while cap < capacity * 2 { cap *= 2 }
        keys = [Int64](repeating: -1, count: cap)
        mask = cap - 1
        self.inv = inv
        cx = [Int](repeating: 0, count: cap)
        cy = cx
        cz = cx
        start = cx
        count = cx
        cursor = cx
        occupied = [Int](repeating: 0, count: max(1, capacity))
        items = occupied
        slotOf = occupied
    }

    /// The slot of a cell, or -1 when the cell is empty (and `make` is false).
    func slot(_ x: Int, _ y: Int, _ z: Int, make: Bool) -> Int {
        let k = ((Int64(x) &+ Self.offset) &* Self.span &+ (Int64(y) &+ Self.offset)) &* Self.span &+ (Int64(z) &+ Self.offset)
        let hx = Int32(truncatingIfNeeded: x) &* 73_856_093
        let hy = Int32(truncatingIfNeeded: y) &* 19_349_663
        let hz = Int32(truncatingIfNeeded: z) &* 83_492_791
        var h = Int(hx ^ hy ^ hz) & mask
        while true {
            let at = keys[h]
            if at == k { return h }
            if at == -1 {
                if !make { return -1 }
                keys[h] = k
                cx[h] = x
                cy[h] = y
                cz[h] = z
                count[h] = 0
                occupied[occupiedCount] = h
                occupiedCount += 1
                return h
            }
            h = (h + 1) & mask
        }
    }

    private func cell(_ v: Double) -> Int {
        let c = (v * inv).rounded(.down)
        guard c.isFinite else { return 0 }
        return Int(max(-1e12, min(1e12, c)))
    }

    /// Puts the points `ids` in their cells.
    func fill(_ ids: [Int], _ f: Field) {
        for i in keys.indices { keys[i] = -1 }
        occupiedCount = 0
        for t in 0 ..< ids.count {
            let i = ids[t]
            let h = slot(cell(f.x[i]), cell(f.y[i]), cell(f.z[i]), make: true)
            count[h] += 1
            slotOf[t] = h
        }
        var acc = 0
        for o in 0 ..< occupiedCount {
            let h = occupied[o]
            start[h] = acc
            cursor[h] = acc
            acc += count[h]
        }
        for t in 0 ..< ids.count {
            let h = slotOf[t]
            items[cursor[h]] = ids[t]
            cursor[h] += 1
        }
    }
}

/// The link force's jiggle (web `seeded(0x5eed)`): a small LCG, so ties break
/// the same way every run.
private nonisolated struct SeededRandom {
    private var s: UInt32

    init(seed: UInt32) {
        s = seed == 0 ? 1 : seed
    }

    mutating func jiggle() -> Double {
        s = s &* 1_664_525 &+ 1_013_904_223
        return (Double(s) / 4_294_967_296 - 0.5) * 1e-6
    }
}

// MARK: - Off the main actor

/// One finished layout: the positions, whether it started from scratch, and
/// the memory it leaves behind. The memory is only a candidate until the view
/// accepts the run (`ConstellationLayoutState.accept`).
nonisolated struct ConstellationLayoutRun: Sendable {
    var positions: [String: SIMD3<Float>]
    var fresh: Bool
    var memory: ConstellationLayout
}

/// Runs a layout off the main actor. Holds no memory of its own: it starts
/// from the memory it is given and hands the next one back with the result.
/// A run whose task is cancelled returns nil.
actor ConstellationLayoutRunner {
    func layout(_ graph: VisibleBrainGraph, from memory: ConstellationLayout) -> ConstellationLayoutRun? {
        guard !Task.isCancelled else { return nil }
        var next = memory
        let result = next.layout(graph)
        guard !Task.isCancelled else { return nil }
        return ConstellationLayoutRun(positions: result.positions, fresh: result.fresh, memory: next)
    }
}

/// The layout memory the sky on screen was drawn from, and the serial of the
/// last placement. A run is committed only when the view accepts it (its task
/// was not cancelled after the run came back), so the next layout is never
/// measured against a sky the user did not see.
nonisolated struct ConstellationLayoutState: Sendable {
    private(set) var memory = ConstellationLayout()
    private(set) var serial = 0

    /// The placement to draw, or nil when the run is dropped (and nothing is remembered).
    mutating func accept(_ run: ConstellationLayoutRun, cancelled: Bool) -> ConstellationPlacement? {
        guard !cancelled else { return nil }
        memory = run.memory
        serial += 1
        return ConstellationPlacement(positions: run.positions, fresh: run.fresh, serial: serial)
    }
}
