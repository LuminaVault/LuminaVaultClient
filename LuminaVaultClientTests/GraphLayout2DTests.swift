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
        Dictionary(uniqueKeysWithValues: zip(nodes.map(\.id), positions))
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
}

// MARK: - Actor

/// A clock tests drive by hand. With `step` set, every reading of `now` also
/// moves it on, so each tick batch appears to take that long.
nonisolated final class TestClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private let state = Mutex(Duration.zero)
    private let step: Duration

    init(step: Duration = .zero) { self.step = step }

    var now: Instant {
        state.withLock { value in
            value += step
            return Instant(offset: value)
        }
    }

    var minimumResolution: Duration { .nanoseconds(1) }

    func advance(by duration: Duration) { state.withLock { $0 += duration } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        while now < deadline { try await Task.sleep(for: .milliseconds(1)) }
    }
}

@Suite(.timeLimit(.minutes(2)))
nonisolated struct GraphLayout2DTests {
    typealias Fixture = LayoutFixtures

    private func waitIdle(_ layout: GraphLayout2D) async throws {
        let deadline = ContinuousClock.now + .seconds(60)
        while await !layout.isIdle {
            try #require(ContinuousClock.now < deadline, "layout never settled")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func aRunEndsWithOneSettledSnapshotAndThenGoesQuiet() async throws {
        let layout = GraphLayout2D(clock: TestClock(step: .milliseconds(10)))
        await layout.setGraph(Fixture.vault(150))
        try await waitIdle(layout)
        let stats = await layout.stats
        #expect(stats.yields > 1, "intermediate frames were published")

        var updates = layout.updates.makeAsyncIterator()
        let last = try #require(await updates.next())
        #expect(last.settled)
        #expect(last.generation == 1)
        #expect(last.ids.count == 156)
        #expect(last.points.count == last.ids.count)

        // Idle: no timer, no polling, nothing more published.
        for _ in 0 ..< 20 { try await Task.sleep(for: .milliseconds(2)) }
        #expect(await layout.stats.yields == stats.yields)
        #expect(await layout.isIdle)

        // A pin wakes it; it settles again.
        await layout.pin("n00003", at: CGPoint(x: 400, y: 400))
        try await waitIdle(layout)
        let woken = try #require(await updates.next())
        #expect(woken.settled)
        #expect(woken.generation == 1)
        let index = try #require(woken.ids.firstIndex(of: "n00003"))
        #expect(woken.points[index] == CGPoint(x: 400, y: 400))
        #expect(await layout.positions()["n00003"] == CGPoint(x: 400, y: 400))
    }

    @Test func aSlowConsumerOnlySeesTheLatestSnapshot() async throws {
        let layout = GraphLayout2D(clock: TestClock(step: .milliseconds(10)))
        await layout.setGraph(Fixture.vault(150))
        try await waitIdle(layout)
        #expect(await layout.stats.yields > 2)
        await layout.stop()
        var seen: [LayoutSnapshot] = []
        for await snapshot in layout.updates { seen.append(snapshot) }
        #expect(seen.count == 1)
        #expect(seen.first?.settled == true)
    }

    @Test func snapshotsAreThrottledByTheClock() async throws {
        // Time never moves: only the first batch and the settle are published.
        let layout = GraphLayout2D(clock: TestClock())
        await layout.setGraph(Fixture.vault(150))
        try await waitIdle(layout)
        #expect(await layout.stats.yields == 2)
    }

    @Test func aSecondGraphMidRunContinuesTheSameLoopForTheNewGeneration() async throws {
        // A still clock publishes the first batch, then nothing until settled.
        let layout = GraphLayout2D(clock: TestClock())
        var updates = layout.updates.makeAsyncIterator()
        await layout.setGraph(Fixture.vault(1000))
        let first = try #require(await updates.next())
        #expect(first.generation == 1)
        #expect(!first.settled)
        try #require(await !layout.isIdle)

        let second = Fixture.vault(120, prefix: "m")
        await layout.setGraph(second)
        var after: [LayoutSnapshot] = []
        while let next = await updates.next() {
            after.append(next)
            if next.settled { break }
        }
        #expect(after.allSatisfy { $0.generation == 2 })
        #expect(after.last?.settled == true)
        #expect(Set(after.last?.ids ?? []) == Set(second.nodes.map(\.id)))
        #expect(await layout.stats.loopStarts == 1)
    }

    @Test func quietModePublishesOnlyTheSettledSnapshot() async throws {
        let layout = GraphLayout2D(clock: TestClock(step: .milliseconds(10)))
        await layout.setQuiet(true)
        await layout.setGraph(Fixture.vault(150))
        try await waitIdle(layout)
        #expect(await layout.stats.yields == 1)
        await layout.pin("n00001", at: .zero)
        try await waitIdle(layout)
        #expect(await layout.stats.yields == 2)
        var updates = layout.updates.makeAsyncIterator()
        #expect(await updates.next()?.settled == true)
    }

    @Test func everyGraphGetsANewGenerationEvenWhenNothingMoves() async throws {
        let layout = GraphLayout2D(clock: TestClock())
        let graph = Fixture.vault(20)
        await layout.setGraph(graph)
        try await waitIdle(layout)
        await layout.setGraph(graph)
        try await waitIdle(layout)
        var updates = layout.updates.makeAsyncIterator()
        let snapshot = try #require(await updates.next())
        #expect(snapshot.generation == 2)
        #expect(snapshot.settled)
    }

    @Test func stopFinishesTheStreamAndIgnoresLaterGraphs() async throws {
        let layout = GraphLayout2D(clock: TestClock())
        await layout.setGraph(Fixture.vault(1000))
        await layout.stop()
        #expect(await layout.isIdle)
        var count = 0
        for await _ in layout.updates { count += 1 }
        #expect(count <= 1)
        let yields = await layout.stats.yields
        await layout.setGraph(Fixture.vault(10))
        await layout.pin("n00001", at: .zero)
        #expect(await layout.isIdle)
        #expect(await layout.stats.yields == yields)
    }

    @Test func releasingTheActorMidRunEndsTheLoopAndTheStream() async throws {
        weak var weakLayout: GraphLayout2D?
        let updates: AsyncStream<LayoutSnapshot>
        do {
            let layout = GraphLayout2D(clock: TestClock())
            weakLayout = layout
            updates = layout.updates
            await layout.setGraph(Fixture.vault(1000))
            #expect(await !layout.isIdle)
        }
        let deadline = ContinuousClock.now + .seconds(10)
        while weakLayout != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(weakLayout == nil, "the run loop kept the actor alive")
        var count = 0
        for await _ in updates { count += 1 }
        #expect(count <= 1)
    }
}
