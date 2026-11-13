// The 2D force layout: the pure simulation, the id hash it seeds from (ported
// from the web app so both platforms place a newcomer alike), and the actor
// that runs it off the main actor and streams snapshots.

import CoreGraphics
import Foundation
@testable import LuminaVaultClient
import LuminaVaultShared
import Synchronization
import Testing

// MARK: - Fixtures

nonisolated enum LayoutFixtures {
    static func note(_ id: String, weight: Int = 1) -> BrainGraphNodeDTO {
        BrainGraphNodeDTO(id: id, kind: .note, label: id, weight: weight)
    }

    static func hub(_ id: String, _ kind: BrainNodeKindDTO, weight: Int) -> BrainGraphNodeDTO {
        BrainGraphNodeDTO(id: id, kind: kind, label: id, weight: weight)
    }

    static func edge(_ from: String, _ to: String, _ kind: BrainLinkKindDTO) -> BrainGraphEdgeDTO {
        BrainGraphEdgeDTO(from: from, to: to, kind: kind)
    }

    static func graph(_ nodes: [BrainGraphNodeDTO], _ edges: [BrainGraphEdgeDTO]) -> VisibleBrainGraph {
        VisibleBrainGraph(nodes: nodes, edges: edges, index: BrainGraphIndex())
    }

    /// `count` notes, each linking to one or two earlier notes chosen by hash,
    /// plus a tag hub for every 25 notes and a few Similar edges: a graph shaped
    /// like a real vault. Weights are the edge counts, as the server sends them.
    static func vault(_ count: Int, prefix: String = "n") -> VisibleBrainGraph {
        let ids = (0 ..< count).map { String(format: "\(prefix)%05d", $0) }
        var edges: [BrainGraphEdgeDTO] = []
        for i in 1 ..< max(1, count) {
            let h = BrainIDHash.mix32(UInt32(truncatingIfNeeded: i) &* 2_654_435_761)
            edges.append(edge(ids[i], ids[Int(h % UInt32(i))], .link))
            if h.isMultiple(of: 3), i > 2 { edges.append(edge(ids[i], ids[Int((h >> 8) % UInt32(i))], .source)) }
            if h.isMultiple(of: 17), i > 2 { edges.append(edge(ids[i], ids[Int((h >> 4) % UInt32(i))], .similar)) }
        }
        var hubs: [BrainGraphNodeDTO] = []
        for t in 0 ..< count / 25 {
            let tag = "tag:\(prefix)\(t)"
            for k in 0 ..< 6 { edges.append(edge(ids[(t * 25 + k * 4) % count], tag, .tag)) }
            hubs.append(hub(tag, .tag, weight: 6))
        }
        var weight: [String: Int] = [:]
        for e in edges {
            weight[e.from, default: 0] += 1
            weight[e.to, default: 0] += 1
        }
        let notes = ids.map { note($0, weight: weight[$0] ?? 0) }
        return graph(notes + hubs, edges)
    }

    /// One author hub linked to every one of `count` notes, and nothing else.
    static func singleAuthor(_ count: Int) -> VisibleBrainGraph {
        let author = "author:user:AAAAAAAA-0000-4000-8000-000000000001"
        let ids = (0 ..< count).map { String(format: "a%05d", $0) }
        return graph(
            ids.map { note($0, weight: 1) } + [hub(author, .author, weight: count)],
            ids.map { edge($0, author, .author) }
        )
    }
}

extension ForceSimulation2D {
    /// Ticks until settled; returns how many ticks that took.
    @discardableResult
    nonisolated mutating func settle(maxTicks: Int = 2000) -> Int {
        var ticks = 0
        while ticks < maxTicks {
            ticks += 1
            if !tick() { break }
        }
        return ticks
    }

    nonisolated func byID() -> [String: CGPoint] {
        Dictionary(zip(nodes.map(\.id), positions), uniquingKeysWith: { first, _ in first })
    }

    /// The smallest gap between two circles drawn at their radii; negative is an overlap.
    nonisolated func smallestGap() -> CGFloat {
        var gap = CGFloat.infinity
        for i in positions.indices {
            for j in positions.indices where j > i {
                let d = hypot(positions[i].x - positions[j].x, positions[i].y - positions[j].y)
                gap = min(gap, d - nodes[i].radius - nodes[j].radius)
            }
        }
        return gap
    }
}

private nonisolated func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
}

/// Distance between two ids' points; NaN (failing any comparison) if either is missing.
private nonisolated func distance(in at: [String: CGPoint], _ a: String, _ b: String) -> CGFloat {
    guard let p = at[a], let q = at[b] else { return .nan }
    return distance(p, q)
}

// MARK: - Id hash

nonisolated struct BrainIDHashTests {
    @Test func isFNV1aOverUTF16CodeUnits() {
        #expect(BrainIDHash.hashID("") == 0x811C_9DC5)
        #expect(BrainIDHash.hashID("a") == 0xE40C_292C)
        #expect(BrainIDHash.hashID("foobar") == 0xBF9C_F968)
        #expect(BrainIDHash.hashID("note-1") == 0x6B0E_4893)
        #expect(BrainIDHash.hashID("AAAAAAAA-0000-4000-8000-000000000002") == 0x87F6_3A87)
        #expect(BrainIDHash.hashID("a", seed: 7) == 0x6600_A092)
        // Outside the BMP the web hashes two UTF-16 units, not one scalar.
        #expect(BrainIDHash.hashID("é😀x") == 0x269E_8C9B)
    }

    @Test func mix32IsTheMurmur3Finaliser() {
        #expect(BrainIDHash.mix32(0) == 0)
        #expect(BrainIDHash.mix32(1) == 0x514E_28B7)
        #expect(BrainIDHash.mix32(2) == 0x30F4_C306)
        #expect(BrainIDHash.mix32(0xFFFF_FFFF) == 0x81F1_6F39)
        #expect(BrainIDHash.mix32(123_456_789) == 0xBA60_D89A)
    }

    /// Values printed by the web's `startPosition` for the same ids.
    @Test func startPositionMatchesTheWeb() {
        let p = ForceSimulation2D.startPosition(id: "note-1", sum: CGPoint(x: 10, y: 20), count: 2)
        #expect(abs(p.x - 7.770734855905175) < 1e-12)
        #expect(abs(p.y - 6.823357777670026) < 1e-12)
        let q = ForceSimulation2D.startPosition(id: "note-1", sum: .zero, count: 0)
        #expect(abs(q.x - 10.390255709644407) < 1e-12)
        #expect(abs(q.y - -11.912408333737403) < 1e-12)
        let r = ForceSimulation2D.startPosition(id: "tag:go", sum: CGPoint(x: 10, y: 20), count: 2)
        #expect(abs(r.x - 3.6058460026979446) < 1e-12)
        #expect(abs(r.y - 9.31731498427689) < 1e-12)
    }
}

// MARK: - Simulation

nonisolated struct ForceSimulation2DTests {
    typealias Fixture = LayoutFixtures

    private static func simulation(_ graph: VisibleBrainGraph) -> ForceSimulation2D {
        var sim = ForceSimulation2D()
        sim.setGraph(graph)
        return sim
    }

    @Test func radiusFollowsTheWebFormula() {
        #expect(ForceSimulation2D.nodeRadius(weight: 0, isHub: false) == 4)
        #expect(abs(ForceSimulation2D.nodeRadius(weight: 4, isHub: false) - 7.2) < 1e-9)
        #expect(ForceSimulation2D.nodeRadius(weight: 100, isHub: false) == 12)
        #expect(ForceSimulation2D.nodeRadius(weight: 0, isHub: true) == 3)
        #expect(ForceSimulation2D.nodeRadius(weight: 4, isHub: true) == 5)
        #expect(ForceSimulation2D.nodeRadius(weight: 100, isHub: true) == 9)
        #expect(ForceSimulation2D.nodeRadius(weight: -3, isHub: false) == 4)
    }

    @Test func inputIsSortedByIDWithDistancesByKind() {
        let graph = Fixture.graph(
            [Fixture.note("b"), Fixture.note("a"), Fixture.hub("tag:x", .tag, weight: 2), Fixture.note("c")],
            [
                Fixture.edge("b", "tag:x", .tag), Fixture.edge("a", "b", .link), Fixture.edge("c", "a", .similar),
                Fixture.edge("a", "c", .source), Fixture.edge("a", "a", .link), Fixture.edge("a", "ghost", .link),
            ]
        )
        let input = ForceSimulation2D.input(for: graph)
        #expect(input.nodes.map(\.id) == ["a", "b", "c", "tag:x"])
        #expect(input.nodes.map(\.isHub) == [false, false, false, true])
        let links = input.links.map { "\($0.from)-\($0.to)-\(Int($0.distance))" }
        #expect(links == ["0-1-60", "0-2-60", "1-3-40", "2-0-90"])
    }

    @Test func isDeterministicForTheSameInputInAnyOrder() {
        let graph = Fixture.vault(300)
        let shuffled = Fixture.graph(graph.nodes.reversed(), graph.edges.reversed())
        var a = Self.simulation(graph)
        var b = Self.simulation(shuffled)
        for _ in 0 ..< 60 {
            _ = a.tick()
            _ = b.tick()
        }
        #expect(a.byID() == b.byID())
    }

    @Test func freshGraphStartsHotAndSettlesBelowTheThreshold() {
        var sim = Self.simulation(Fixture.vault(200))
        #expect(sim.alpha == 1)
        let ticks = sim.settle()
        #expect(ticks <= 300)
        #expect(sim.alpha < ForceSimulation2D.settleAlpha)
        #expect(sim.tick() == false)
        #expect(sim.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    @Test func knownIDsKeepTheirPositionsWhenTheNodeSetChanges() throws {
        let graph = Fixture.vault(120)
        var sim = Self.simulation(graph)
        sim.settle()
        let before = sim.byID()

        // Drop one note, add one linked to n00007.
        let dropped = "n00050"
        let next = Fixture.graph(
            graph.nodes.filter { $0.id != dropped } + [Fixture.note("zz-new")],
            graph.edges.filter { $0.from != dropped && $0.to != dropped } + [Fixture.edge("zz-new", "n00007", .link)]
        )
        sim.setGraph(next)
        let after = sim.byID()
        for (id, p) in after where id != "zz-new" {
            #expect(before[id] == p, "\(id) moved")
        }
        #expect(after[dropped] == nil)
        #expect(sim.alpha == ForceSimulation2D.reheatAlpha)

        // The newcomer starts within the jitter of its one placed neighbour.
        let anchor = try #require(before["n00007"])
        let seeded = try #require(after["zz-new"])
        #expect(abs(seeded.x - anchor.x) <= 4)
        #expect(abs(seeded.y - anchor.y) <= 4)
        #expect(seeded == ForceSimulation2D.startPosition(id: "zz-new", sum: anchor, count: 1))
    }

    @Test func anUnchangedGraphDoesNotReheat() {
        let graph = Fixture.vault(80)
        var sim = Self.simulation(graph)
        sim.settle()
        let before = sim.positions
        sim.setGraph(Fixture.graph(graph.nodes.reversed(), graph.edges))
        #expect(sim.alpha < ForceSimulation2D.settleAlpha)
        #expect(sim.tick() == false)
        #expect(sim.positions == before)
    }

    @Test func hiddenIDsAreParkedAndRestored() throws {
        let graph = Fixture.vault(120)
        var sim = Self.simulation(graph)
        sim.settle()
        let hidden = "n00033"
        let parkedAt = try #require(sim.byID()[hidden])

        sim.setGraph(Fixture.graph(
            graph.nodes.filter { $0.id != hidden },
            graph.edges.filter { $0.from != hidden && $0.to != hidden }
        ))
        #expect(sim.isFresh(["x", "y"]))
        #expect(!sim.isFresh(["x", hidden]))
        sim.settle()
        sim.setGraph(graph)
        #expect(sim.byID()[hidden] == parkedAt)
    }

    @Test func aFreshGraphDropsParkedPositions() throws {
        let graph = Fixture.vault(60)
        var sim = Self.simulation(graph)
        sim.settle()
        let hidden = "n00010"
        let parkedAt = try #require(sim.byID()[hidden])
        sim.setGraph(Fixture.graph(graph.nodes.filter { $0.id != hidden }, []))

        // Nothing in this graph is known: it is fresh, and hot.
        let other = Fixture.vault(30, prefix: "o")
        #expect(sim.isFresh(other.nodes.map(\.id)))
        sim.setGraph(other)
        #expect(sim.alpha == 1)
        sim.settle()

        sim.setGraph(Fixture.graph(other.nodes + [Fixture.note(hidden)], other.edges))
        #expect(sim.byID()[hidden] != parkedAt)
        #expect(sim.byID()[hidden] == ForceSimulation2D.startPosition(id: hidden, sum: .zero, count: 0))
    }

    @Test func anEmptyGraphIsNeverFreshAndKeepsMemory() throws {
        let graph = Fixture.vault(40)
        var sim = Self.simulation(graph)
        sim.settle()
        let was = sim.byID()
        #expect(!sim.isFresh([]))
        sim.setGraph(Fixture.graph([], []))
        #expect(sim.positions.isEmpty)
        #expect(sim.tick() == false)
        sim.setGraph(graph)
        #expect(sim.byID() == was)
    }

    @Test func aLinkedPairEndsCloserThanAnUnlinkedPair() {
        var small = Self.simulation(Fixture.graph(
            [Fixture.note("a"), Fixture.note("b"), Fixture.note("c"), Fixture.note("d")],
            [Fixture.edge("a", "b", .link)]
        ))
        small.settle()
        let p = small.byID()
        #expect(distance(in: p, "a", "b") < distance(in: p, "c", "d"))

        let graph = Fixture.vault(300)
        var sim = Self.simulation(graph)
        sim.settle()
        let at = sim.byID()
        let linked = graph.edges.map { distance(in: at, $0.from, $0.to) }
        let linkedMean = linked.reduce(0, +) / CGFloat(linked.count)
        let ids = graph.nodes.map(\.id)
        var unlinked: [CGFloat] = []
        for i in stride(from: 0, to: ids.count - 7, by: 3) {
            let a = ids[i], b = ids[i + 7]
            if graph.edges.contains(where: { ($0.from == a && $0.to == b) || ($0.from == b && $0.to == a) }) { continue }
            unlinked.append(distance(in: at, a, b))
        }
        let unlinkedMean = unlinked.reduce(0, +) / CGFloat(unlinked.count)
        #expect(linkedMean * 2 < unlinkedMean, "linked \(linkedMean) unlinked \(unlinkedMean)")
    }

    @Test func noTwoPointsOverlapAfterSettling() {
        var sim = Self.simulation(Fixture.vault(400))
        sim.settle()
        let gap = sim.smallestGap()
        #expect(gap >= 0, "closest pair overlaps by \(-gap)")
    }

    @Test func aSingleAuthorGraphSpreadsWithoutOverlap() throws {
        let graph = Fixture.singleAuthor(1000)
        var sim = Self.simulation(graph)
        let ticks = sim.settle()
        #expect(ticks <= 300)
        #expect(sim.smallestGap() >= 0)
        let at = sim.byID()
        let hubID = try #require(graph.nodes.last?.id)
        let reach = graph.nodes.dropLast().map { distance(in: at, $0.id, hubID) }
        let hub = try #require(at[hubID])
        // A thousand points cannot sit on one 40 pt ring: they fill a disc
        // around the hub instead of piling onto it.
        #expect(try #require(reach.max()) > 150)
        #expect(try #require(reach.min()) > 5)
        #expect(hypot(hub.x, hub.y) < 60)
    }

    @Test func aFresh1000PointGraphSettlesWithinBudget() {
        var sim = Self.simulation(Fixture.vault(1000))
        let clock = ContinuousClock()
        var ticks = 0
        let elapsed = clock.measure { ticks = sim.settle() }
        #expect(ticks <= 300)
        #if !DEBUG
            #expect(elapsed < .milliseconds(600))
        #else
            _ = elapsed
        #endif
    }

    @Test func aPinnedPointStaysWhereItIsPutAndReheats() {
        var sim = Self.simulation(Fixture.vault(60))
        sim.settle()
        let target = CGPoint(x: 300, y: -200)
        sim.pin(5, at: target)
        #expect(sim.positions[5] == target)
        #expect(sim.alpha == ForceSimulation2D.reheatAlpha)
        for _ in 0 ..< 20 { _ = sim.tick() }
        #expect(sim.positions[5] == target)

        sim.pin(5, at: nil)
        sim.settle()
        #expect(sim.alpha < ForceSimulation2D.settleAlpha)
        #expect(sim.positions[5] != target)
    }

    @Test func aPinSurvivesAGraphChangeForTheSameID() {
        let graph = Fixture.vault(40)
        var sim = Self.simulation(graph)
        let id = sim.nodes[3].id
        let target = CGPoint(x: -120, y: 80)
        sim.pin(3, at: target)
        sim.setGraph(Fixture.graph(graph.nodes + [Fixture.note("aaa-first")], graph.edges))
        sim.settle()
        #expect(sim.byID()[id] == target)
    }

    @Test func nonFinitePinsAreIgnoredAndFarPinsClamped() {
        var sim = Self.simulation(Fixture.vault(60))
        sim.settle()
        let before = sim.positions
        let cold = sim.alpha
        for bad in [CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 0, y: CGFloat.infinity), CGPoint(x: -CGFloat.infinity, y: CGFloat.nan)] {
            sim.pin(4, at: bad)
        }
        #expect(sim.positions == before)
        #expect(sim.alpha == cold)
        #expect(sim.tick() == false)

        sim.pin(4, at: CGPoint(x: 1e9, y: -1e12))
        #expect(sim.positions[4] == CGPoint(x: 100_000, y: -100_000))
        sim.settle()
        #expect(sim.positions[4] == CGPoint(x: 100_000, y: -100_000))
        #expect(sim.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    @Test func anEmptyGraphTicksCold() {
        var sim = Self.simulation(Fixture.vault(20))
        sim.setGraph(Fixture.graph([], []))
        #expect(sim.alpha > 0)
        #expect(sim.tick() == false)
        #expect(sim.alpha == 0)
    }

    @Test func aFreshGraphLaysOutTheSameWhateverCameBefore() {
        let graph = Fixture.singleAuthor(1000)
        var alone = Self.simulation(graph)
        alone.settle()

        var after = Self.simulation(Fixture.vault(30, prefix: "o"))
        for _ in 0 ..< 7 { _ = after.tick() }
        #expect(after.isFresh(graph.nodes.map(\.id)))
        after.setGraph(graph)
        after.settle()
        #expect(after.byID() == alone.byID())
    }

    /// Two ids that are different strings on the wire (NFC and NFD, or a
    /// character outside the BMP) stay two points, in the web's code-unit order.
    @Test func idsThatDifferOnTheWireStayTwoPoints() {
        let nfc = "tag:caf\u{E9}", nfd = "tag:cafe\u{301}"
        let astral = "\u{1F600}x", halfwidth = "\u{FF61}x"
        #expect(nfc == nfd, "Swift's own String equality merges them")
        let graph = Fixture.graph(
            [Fixture.note(halfwidth), Fixture.note(nfc), Fixture.note(astral), Fixture.note(nfd)],
            [Fixture.edge(nfd, astral, .link), Fixture.edge(nfc, halfwidth, .source)]
        )
        let input = ForceSimulation2D.input(for: graph)
        #expect(input.nodes.map { Array($0.id.utf16) } == [nfd, nfc, astral, halfwidth].map { Array($0.utf16) })
        #expect(input.links.map { "\($0.from)-\($0.to)" } == ["0-2", "1-3"])

        var sim = ForceSimulation2D()
        sim.setGraph(graph)
        #expect(sim.nodes.count == 4)
        #expect(sim.index(of: nfd) == 0)
        #expect(sim.index(of: nfc) == 1)
        sim.settle()
        #expect(sim.positions[0] != sim.positions[1])
    }

    /// 1,000 newcomers seeded onto one placed hub: the crowded clump must
    /// spread without flinging the hub. d3, on the same input, moves the hub
    /// at most 92 pt and settles the group at about (29, -42).
    @Test func aBurstOfNewcomersOntoOneHubDoesNotFlingIt() throws {
        let author = "author:user:AAAAAAAA-0000-4000-8000-000000000001"
        let ids = ["z-seed"] + (0 ..< 1000).map { String(format: "a%05d", $0) }
        let hub = Fixture.hub(author, .author, weight: ids.count)
        var sim = Self.simulation(Fixture.graph([hub, Fixture.note("z-seed")], [Fixture.edge("z-seed", author, .author)]))
        sim.settle()
        let start = try #require(sim.byID()[author])

        sim.setGraph(Fixture.graph([hub] + ids.map { Fixture.note($0) }, ids.map { Fixture.edge($0, author, .author) }))
        let h = try #require(sim.index(of: author))
        var furthest: CGFloat = 0
        var ticks = 0
        while ticks < 400 {
            ticks += 1
            let more = sim.tick()
            furthest = max(furthest, distance(sim.positions[h], start))
            if !more { break }
        }
        #expect(ticks <= 300)
        #expect(furthest < 300, "hub flung \(furthest) pt")
        let members = sim.positions.indices.filter { $0 != h }
        let centroid = CGPoint(
            x: members.map { sim.positions[$0].x }.reduce(0, +) / CGFloat(members.count),
            y: members.map { sim.positions[$0].y }.reduce(0, +) / CGFloat(members.count)
        )
        #expect(hypot(centroid.x, centroid.y) < 200, "group settled at \(centroid)")
        #expect(sim.smallestGap() >= 0)
    }

    /// Per tick while the layout cools: the largest step any point takes, the
    /// summed squared steps (kinetic energy), and how many points step back
    /// against their last step by more than a quarter point (shimmer).
    private struct Motion {
        var maxStep: [CGFloat] = []
        var energy: [CGFloat] = []
        var reversals: [Int] = []
        var alpha: [CGFloat] = []
    }

    private static func cool(_ sim: inout ForceSimulation2D) -> Motion {
        var out = Motion()
        var last = sim.positions
        var lastStep = [CGPoint](repeating: .zero, count: last.count)
        var ticks = 0
        while ticks < 400 {
            ticks += 1
            let more = sim.tick()
            var biggest: CGFloat = 0, energy: CGFloat = 0, back = 0
            for i in sim.positions.indices {
                let step = CGPoint(x: sim.positions[i].x - last[i].x, y: sim.positions[i].y - last[i].y)
                let length = hypot(step.x, step.y)
                biggest = max(biggest, length)
                energy += length * length
                if length > 0.25, step.x * lastStep[i].x + step.y * lastStep[i].y < 0 { back += 1 }
                lastStep[i] = step
            }
            out.maxStep.append(biggest)
            out.energy.append(energy)
            out.reversals.append(back)
            out.alpha.append(sim.alpha)
            last = sim.positions
            if !more { break }
        }
        return out
    }

    /// A crowded cluster (1,000 points on one hub) comes to rest instead of
    /// shimmering: once cool, kinetic energy only falls (5% slack per tick),
    /// and almost no point steps back and forth. Collision summed against
    /// positions predicted before any correction measured, over the last 30
    /// ticks, 730 (author) and 713 (burst) of 1,000 points reversing in one
    /// tick and a largest step of 1.2-1.4 pt at rest; resolved pair by pair,
    /// 2 and 0, and 0.3-0.4 pt.
    @Test(arguments: ["author", "burst"])
    func aCrowdedClusterComesToRestWithoutShimmer(_ shape: String) {
        var sim = ForceSimulation2D()
        let author = "author:user:AAAAAAAA-0000-4000-8000-000000000001"
        if shape == "author" {
            sim.setGraph(Fixture.singleAuthor(1000))
        } else {
            sim.setGraph(Fixture.graph([Fixture.hub(author, .author, weight: 2), Fixture.note("z-seed")], [Fixture.edge("z-seed", author, .author)]))
            sim.settle()
            let ids = ["z-seed"] + (0 ..< 1000).map { String(format: "a%05d", $0) }
            sim.setGraph(Fixture.graph(
                [Fixture.hub(author, .author, weight: ids.count)] + ids.map { Fixture.note($0) },
                ids.map { Fixture.edge($0, author, .author) }
            ))
        }
        let m = Self.cool(&sim)
        let late = m.alpha.indices.filter { m.alpha[$0] < 0.1 }
        let rises = late.dropFirst().filter { m.energy[$0] > m.energy[$0 - 1] * 1.05 }.count
        let tail = m.reversals.suffix(30)
        let worstReversals = tail.max() ?? 0
        #expect(m.alpha.count <= 300)
        #expect(rises == 0, "kinetic energy rose on \(rises) late ticks")
        #expect(worstReversals <= 10, "\(worstReversals) points shimmer in one late tick")
        #expect(sim.smallestGap() >= 0)
    }

    /// A point held far away stays out of the grid's extent, so the rest lay
    /// out exactly as if it were not there (it has no links to pull them).
    @Test func aFarPinLeavesTheRestUntouched() {
        let graph = Fixture.vault(300)
        var alone = Self.simulation(graph)
        alone.settle()

        let far = "zzz-far"
        var held = Self.simulation(Fixture.graph(graph.nodes + [Fixture.note(far)], graph.edges))
        let index = held.nodes.count - 1
        #expect(held.nodes[index].id == far)
        held.pin(index, at: CGPoint(x: 90_000, y: 90_000))
        held.settle()
        var rest = held.byID()
        rest[far] = nil
        #expect(rest == alone.byID())
    }

    #if DEBUG
        /// A Debug-checkable stand-in for the release timing: the work per tick.
        /// By construction a point visits at most 9 cells × 24 exact pairs (a
        /// crowded cell counts as one body), so 216. Measured release means
        /// per point per tick over a settle: vault 24, single author 95,
        /// clump 87; the bound of 120 leaves 25% headroom over the worst.
        @Test(arguments: ["vault", "author", "clump"])
        func nearFieldWorkPerTickIsBounded(_ shape: String) {
            var sim = ForceSimulation2D()
            switch shape {
            case "vault": sim.setGraph(Fixture.vault(1000))
            case "author": sim.setGraph(Fixture.singleAuthor(1000))
            default:
                let author = "author:user:AAAAAAAA-0000-4000-8000-000000000001"
                sim.setGraph(Fixture.graph(
                    [Fixture.hub(author, .author, weight: 2), Fixture.note("z-seed")],
                    [Fixture.edge("z-seed", author, .author)]
                ))
                sim.settle()
                let ids = ["z-seed"] + (0 ..< 1000).map { String(format: "a%05d", $0) }
                sim.setGraph(Fixture.graph(
                    [Fixture.hub(author, .author, weight: ids.count)] + ids.map { Fixture.note($0) },
                    ids.map { Fixture.edge($0, author, .author) }
                ))
            }
            var ticks = 0, busiest = 0
            var perPoint = 0.0
            while ticks < 400 {
                ticks += 1
                let more = sim.tick()
                let visits = sim.lastTickPairVisits
                busiest = max(busiest, visits.maxPerPoint)
                perPoint += Double(visits.total) / Double(sim.nodes.count)
                if !more { break }
            }
            #expect(ticks <= 300)
            #expect(busiest <= 9 * ForceSimulation2D.cellSampleLimit)
            #expect(perPoint / Double(ticks) < 120, "mean \(perPoint / Double(ticks)) pairs per point per tick")
        }

        @Test func aNonFinitePositionNeverTrapsTheGrid() {
            var sim = Self.simulation(Fixture.vault(80))
            sim.overwritePositionForTesting(3, CGPoint(x: CGFloat.nan, y: 4))
            sim.overwritePositionForTesting(9, CGPoint(x: CGFloat.infinity, y: -CGFloat.infinity))
            sim.settle()
            #expect(sim.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        }

    #endif
}

// MARK: - Actor

/// A clock that moves only when told. `sleep(until:)` parks until `advance`
/// reaches its deadline, and ends early with `CancellationError` when its task
/// is cancelled.
nonisolated final class ManualClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper: Sendable {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State: Sendable {
        var now = Instant(offset: .zero)
        var sleepers: [Sleeper] = []
        var cancelledEarly: Set<Int> = []
        var nextID = 0
        var sleepCalls = 0
    }

    private let state = Mutex(State())

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .nanoseconds(1) }
    var sleeperCount: Int { state.withLock { $0.sleepers.count } }
    /// How many times anything has slept on this clock.
    var sleepCalls: Int { state.withLock { $0.sleepCalls } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = state.withLock { s in
            s.nextID += 1
            s.sleepCalls += 1
            return s.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                enum Action { case resume, cancel, park }
                let action: Action = state.withLock { s in
                    if s.cancelledEarly.remove(id) != nil { return .cancel }
                    if deadline <= s.now { return .resume }
                    s.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return .park
                }
                switch action {
                case .resume: continuation.resume()
                case .cancel: continuation.resume(throwing: CancellationError())
                case .park: break
                }
            }
        } onCancel: {
            let sleeper: Sleeper? = state.withLock { s in
                if let i = s.sleepers.firstIndex(where: { $0.id == id }) { return s.sleepers.remove(at: i) }
                s.cancelledEarly.insert(id)
                return nil
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time on and wakes every sleeper now due.
    func advance(by duration: Duration) {
        let due: [Sleeper] = state.withLock { s in
            s.now = s.now.advanced(by: duration)
            let now = s.now
            let ready = s.sleepers.filter { $0.deadline <= now }
            s.sleepers.removeAll { $0.deadline <= now }
            return ready
        }
        for sleeper in due { sleeper.continuation.resume() }
    }

    /// Waits (in real time, briefly) until `count` sleepers are parked.
    func parked(_ count: Int) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(20)
        while sleeperCount != count {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }
}

@Suite(.timeLimit(.minutes(2)))
nonisolated struct GraphLayout2DTests {
    typealias Fixture = LayoutFixtures
    static let frame = GraphLayout2D.frameInterval

    private func until(_ what: String, _ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while await !condition() {
            try #require(ContinuousClock.now < deadline, "timed out waiting for \(what)")
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    /// Advances a frame whenever the loop sleeps, until the run settles.
    @discardableResult
    private func drive(_ layout: GraphLayout2D, _ clock: ManualClock) async throws -> Int {
        var frames = 0
        let deadline = ContinuousClock.now + .seconds(60)
        while await !layout.isIdle {
            try #require(ContinuousClock.now < deadline, "layout never settled")
            if clock.sleeperCount > 0 {
                clock.advance(by: Self.frame)
                frames += 1
            } else {
                try await Task.sleep(for: .milliseconds(1))
            }
        }
        return frames
    }

    /// Advances `count` frames, each time waiting for the loop to step and sleep again.
    private func step(_ clock: ManualClock, frames count: Int) async throws {
        for _ in 0 ..< count {
            try #require(await clock.parked(1))
            clock.advance(by: Self.frame)
        }
        try #require(await clock.parked(1))
    }

    // MARK: Pacing

    @Test func withoutTimeNothingTicks() async throws {
        let clock = ManualClock()
        let layout = GraphLayout2D(clock: clock)
        // Held: dropping the stream would count as the subscriber leaving.
        let stream = await layout.updates()
        await layout.setGraph(Fixture.vault(150))
        try #require(await clock.parked(1))
        try await Task.sleep(for: .milliseconds(20))
        #expect(await layout.stats.ticks == 0)
        #expect(await layout.stats.yields == 0)
        #expect(await !layout.isIdle)
        withExtendedLifetime(stream) {}
    }

    @Test func eachFrameIsTwoTicksAndOneSnapshot() async throws {
        let clock = ManualClock()
        let layout = GraphLayout2D(clock: clock)
        var updates = await layout.updates().makeAsyncIterator()
        await layout.setGraph(Fixture.vault(150))
        try await step(clock, frames: 1)
        #expect(await layout.stats.ticks == 2)
        #expect(await layout.stats.yields == 1)
        let first = try #require(await updates.next())
        #expect(first.generation == 1)
        #expect(!first.settled)
        try await step(clock, frames: 1)
        #expect(await layout.stats.ticks == 4)
        #expect(await layout.stats.yields == 2)
    }

    @Test func aStallGivesOneStepNotACatchUpBurst() async throws {
        let clock = ManualClock()
        let layout = GraphLayout2D(clock: clock)
        await layout.setGraph(Fixture.vault(150))
        try await step(clock, frames: 1)
        clock.advance(by: .seconds(1))
        try #require(await clock.parked(1))
        #expect(await layout.stats.ticks == 4)
        #expect(await layout.stats.yields == 2)
    }

    @Test func aDragIsPacedLikeASettle() async throws {
        let clock = ManualClock()
        let layout = GraphLayout2D(clock: clock)
        await layout.setGraph(Fixture.vault(60))
        try await drive(layout, clock)
        let ticks = await layout.stats.ticks
        for k in 1 ... 5 {
            await layout.pin("n00002", at: CGPoint(x: 10 * CGFloat(k), y: 0))
        }
        try await step(clock, frames: 1)
        #expect(await layout.stats.ticks == ticks + 2)
        #expect(await layout.stats.loopStarts == 2)
        #expect(await layout.positions()["n00002"] == CGPoint(x: 50, y: 0))
    }

    @Test func cancellingWhileAsleepEndsTheLoop() async throws {
        let clock = ManualClock()
        let layout = GraphLayout2D(clock: clock)
        await layout.setGraph(Fixture.vault(150))
        try await step(clock, frames: 2)
        await layout.pause()
        try #require(await clock.parked(0), "the sleeping step was not cancelled")
        let ticks = await layout.stats.ticks
        clock.advance(by: .seconds(5))
        try await Task.sleep(for: .milliseconds(20))
        #expect(await layout.stats.ticks == ticks)
        #expect(await layout.isIdle)
        #expect(clock.sleeperCount == 0)
    }

    @Test func quietModeNeverSleeps() async throws {
        let clock = ManualClock()
        let layout = GraphLayout2D(clock: clock)
        var updates = await layout.updates().makeAsyncIterator()
        await layout.setQuiet(true)
        await layout.setGraph(Fixture.vault(150))
        try await until("settle") { await layout.isIdle }
        #expect(clock.sleepCalls == 0)
        #expect(await layout.stats.yields == 1)
        #expect(await updates.next()?.settled == true)
        await layout.pin("n00001", at: .zero)
        try await until("second settle") { await layout.isIdle }
        #expect(clock.sleepCalls == 0)
        #expect(await layout.stats.yields == 2)
    }

    // MARK: Runs and generations

    @Test func aRunEndsWithOneSettledSnapshotAndThenGoesQuiet() async throws {
        let clock = ManualClock()
        let layout = GraphLayout2D(clock: clock)
        var updates = await layout.updates().makeAsyncIterator()
        await layout.setGraph(Fixture.vault(150))
        let frames = try await drive(layout, clock)
        #expect(frames >= 80)
        let stats = await layout.stats
        #expect(stats.yields == frames)
        let last = try #require(await updates.next())
        #expect(last.settled)
        #expect(last.generation == 1)
        #expect(last.ids.count == 156)
        #expect(last.points.count == last.ids.count)

        // Idle: nothing asleep, nothing ticking, nothing published.
        #expect(clock.sleeperCount == 0)
        clock.advance(by: .seconds(10))
        try await Task.sleep(for: .milliseconds(20))
        #expect(await layout.stats == stats)

        // A pin wakes it; it settles again with the point held.
        await layout.pin("n00003", at: CGPoint(x: 400, y: 400))
        try await drive(layout, clock)
        let woken = try #require(await updates.next())
        #expect(woken.settled)
        let index = try #require(woken.ids.firstIndex(of: "n00003"))
        #expect(woken.points[index] == CGPoint(x: 400, y: 400))
    }

    @Test func aSlowConsumerOnlySeesTheLatestSnapshot() async throws {
        let clock = ManualClock()
        let layout = GraphLayout2D(clock: clock)
        let updates = await layout.updates()
        await layout.setGraph(Fixture.vault(150))
        try await drive(layout, clock)
        #expect(await layout.stats.yields > 2)
        await layout.stop()
        var seen: [LayoutSnapshot] = []
        for await snapshot in updates { seen.append(snapshot) }
        #expect(seen.count == 1)
        #expect(seen.first?.settled == true)
    }

    @Test func aSecondGraphMidRunContinuesTheSameLoopForTheNewGeneration() async throws {
        let clock = ManualClock()
        let layout = GraphLayout2D(clock: clock)
        var updates = await layout.updates().makeAsyncIterator()
        await layout.setGraph(Fixture.vault(300))
        try await step(clock, frames: 1)
        let first = try #require(await updates.next())
        #expect(first.generation == 1)
        #expect(!first.settled)

        let second = Fixture.vault(120, prefix: "m")
        await layout.setGraph(second)
        try await drive(layout, clock)
        let last = try #require(await updates.next())
        #expect(last.generation == 2)
        #expect(last.settled)
        #expect(Set(last.ids) == Set(second.nodes.map(\.id)))
        #expect(await layout.stats.loopStarts == 1)
    }

    @Test func everyGraphGetsANewGenerationEvenWhenNothingMoves() async throws {
        let clock = ManualClock()
        let layout = GraphLayout2D(clock: clock)
        var updates = await layout.updates().makeAsyncIterator()
        let graph = Fixture.vault(20)
        await layout.setGraph(graph)
        try await drive(layout, clock)
        await layout.setGraph(graph)
        try await drive(layout, clock)
        let snapshot = try #require(await updates.next())
        #expect(snapshot.generation == 2)
        #expect(snapshot.settled)
    }

    // MARK: Pause, resume, subscribers

    @Test func pauseMidRunHoldsAndResumeFinishesTheSameGeneration() async throws {
        let clock = ManualClock()
        let layout = GraphLayout2D(clock: clock)
        var updates = await layout.updates().makeAsyncIterator()
        await layout.setGraph(Fixture.vault(150))
        try await step(clock, frames: 3)
        await layout.pause()
        let held = await layout.stats
        clock.advance(by: .seconds(1))
        try await Task.sleep(for: .milliseconds(20))
        #expect(await layout.stats == held)
        #expect(await layout.isPaused)

        await layout.resume()
        #expect(await layout.stats.yields == held.yields + 1)
        try await drive(layout, clock)
        let last = try #require(await updates.next())
        #expect(last.generation == 1)
        #expect(last.settled)
        #expect(await layout.stats.ticks > held.ticks)
    }

    @Test func whilePausedAGraphChangesTheLayoutButRunsNothing() async throws {
        let clock = ManualClock()
        let layout = GraphLayout2D(clock: clock)
        await layout.pause()
        await layout.setGraph(Fixture.vault(40))
        #expect(await layout.isIdle)
        #expect(await layout.positions().count == 41)
        #expect(clock.sleeperCount == 0)
        var updates = await layout.updates().makeAsyncIterator()
        let now = try #require(await updates.next())
        #expect(now.generation == 1)
        #expect(!now.settled)
        #expect(await !layout.isPaused)
        try await drive(layout, clock)
        #expect(await updates.next()?.settled == true)
    }

    @Test func aNewSubscriberAfterACancelledOneGetsTheCurrentSnapshotAndLaterOnes() async throws {
        let clock = ManualClock()
        let layout = GraphLayout2D(clock: clock)
        let firstStream = await layout.updates()
        let consumer = Task { for await _ in firstStream {} }
        await layout.setGraph(Fixture.vault(150))
        try await step(clock, frames: 2)
        consumer.cancel()
        try await until("pause") { await layout.isPaused }

        var updates = await layout.updates().makeAsyncIterator()
        let current = try #require(await updates.next())
        #expect(current.generation == 1)
        #expect(!current.settled)
        try await step(clock, frames: 1)
        let later = try #require(await updates.next())
        #expect(later.points != current.points)
        try await drive(layout, clock)
        #expect(await updates.next()?.settled == true)
    }

    @Test func nobodyListeningMeansNothingTicks() async throws {
        let clock = ManualClock()
        let layout = GraphLayout2D(clock: clock)
        let stream = await layout.updates()
        let consumer = Task { for await _ in stream {} }
        await layout.setGraph(Fixture.vault(150))
        try await step(clock, frames: 1)
        consumer.cancel()
        try await until("pause") { await layout.isPaused }
        let ticks = await layout.stats.ticks
        for _ in 0 ..< 20 { clock.advance(by: Self.frame) }
        try await Task.sleep(for: .milliseconds(20))
        #expect(await layout.stats.ticks == ticks)
        #expect(clock.sleeperCount == 0)
    }

    @Test func aNewSubscriberReplacesTheOldOne() async throws {
        let layout = GraphLayout2D(clock: ManualClock())
        let old = await layout.updates()
        let current = await layout.updates()
        var count = 0
        for await _ in old { count += 1 }
        #expect(count == 0)
        try await Task.sleep(for: .milliseconds(20))
        #expect(await !layout.isPaused, "the old stream's end paused the new subscriber")
        withExtendedLifetime(current) {}
    }

    @Test func aNonFinitePinIsIgnored() async throws {
        let clock = ManualClock()
        let layout = GraphLayout2D(clock: clock)
        await layout.setGraph(Fixture.vault(40))
        try await drive(layout, clock)
        let before = await layout.positions()
        let stats = await layout.stats
        await layout.pin("n00002", at: CGPoint(x: CGFloat.nan, y: 1))
        await layout.pin("n00002", at: CGPoint(x: 1, y: CGFloat.infinity))
        #expect(await layout.isIdle)
        #expect(await layout.stats == stats)
        #expect(await layout.positions() == before)
    }

    // MARK: Ending

    @Test func stopFinishesTheStreamAndIgnoresLaterCommands() async throws {
        let clock = ManualClock()
        let layout = GraphLayout2D(clock: clock)
        let updates = await layout.updates()
        await layout.setGraph(Fixture.vault(300))
        try await step(clock, frames: 1)
        await layout.stop()
        #expect(await layout.isIdle)
        try #require(await clock.parked(0))
        var count = 0
        for await _ in updates { count += 1 }
        #expect(count <= 1)
        let stats = await layout.stats
        await layout.setGraph(Fixture.vault(10))
        await layout.pin("n00001", at: .zero)
        await layout.resume()
        #expect(await layout.isIdle)
        #expect(await layout.stats == stats)
        var late = 0
        for await _ in await layout.updates() { late += 1 }
        #expect(late == 0)
    }

    @Test func releasingTheActorWhileItSleepsEndsTheLoopAndTheStream() async throws {
        let clock = ManualClock()
        weak var weakLayout: GraphLayout2D?
        let updates: AsyncStream<LayoutSnapshot>
        do {
            let layout = GraphLayout2D(clock: clock)
            weakLayout = layout
            updates = await layout.updates()
            await layout.setGraph(Fixture.vault(300))
            try await step(clock, frames: 1)
        }
        try await until("release") { weakLayout == nil }
        try #require(await clock.parked(0), "the run loop is still asleep")
        var count = 0
        for await _ in updates { count += 1 }
        #expect(count <= 1)
    }

    @Test func aPausedActorIsReleasedWhenDropped() async throws {
        let clock = ManualClock()
        weak var weakLayout: GraphLayout2D?
        do {
            let layout = GraphLayout2D(clock: clock)
            weakLayout = layout
            let stream = await layout.updates()
            await layout.setGraph(Fixture.vault(100))
            try await step(clock, frames: 1)
            await layout.pause()
            withExtendedLifetime(stream) {}
        }
        try await until("release") { weakLayout == nil }
        #expect(clock.sleeperCount == 0)
    }
}
