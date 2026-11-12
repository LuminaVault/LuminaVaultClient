// Port of the web app's constellation-layout.test.ts, case by case and in the
// same order. `layoutConstellation` is `ConstellationLayout.layoutConstellation`
// (its counters come back in `cost` instead of a module global);
// `ConstellationMemory.layout` is `ConstellationLayout.place`, which keeps the
// web's Double precision; `layout`, the renderer's entry point, is the same
// numbers as Float and is checked against `place` at the end.

import Foundation
@testable import LuminaVaultClient
import LuminaVaultShared
import Testing

private typealias Vec = SIMD3<Double>

nonisolated private let cloudRadius = ConstellationLayout.cloudRadius

nonisolated private func node(
    _ id: String, _ kind: BrainNodeKindDTO, vault: UUID? = nil, pos: (Double, Double, Double)? = nil, weight: Int = 0
) -> BrainGraphNodeDTO {
    BrainGraphNodeDTO(
        id: id, kind: kind, label: id, vaultID: vault, weight: weight,
        pos: pos.map { GraphPosition3D(x: $0.0, y: $0.1, z: $0.2) }
    )
}

nonisolated private func edge(_ from: String, _ to: String, _ kind: BrainLinkKindDTO) -> BrainGraphEdgeDTO {
    BrainGraphEdgeDTO(from: from, to: to, kind: kind)
}

nonisolated private func build(
    _ nodes: [BrainGraphNodeDTO], _ edges: [BrainGraphEdgeDTO], _ filters: BrainGraphFilters? = nil
) -> VisibleBrainGraph {
    let raw = BrainGraphResponse(generatedAt: Date(timeIntervalSince1970: 0), vaults: [], nodes: nodes, edges: edges)
    return BrainGraphModel.visible(raw, filters: filters ?? BrainGraphModel.defaultFilters())
}

nonisolated private func length(_ v: Vec) -> Double { hypot(hypot(v.x, v.y), v.z) }
nonisolated private func distance(_ a: Vec, _ b: Vec) -> Double { length(a - b) }

nonisolated private func positions(_ graph: VisibleBrainGraph) -> [String: Vec] {
    ConstellationLayout.layoutConstellation(graph).positions
}

nonisolated private func at(_ out: [String: Vec], _ id: String) -> Vec {
    out[id] ?? Vec(.nan, .nan, .nan)
}

nonisolated private func finite(_ v: Vec?) -> Bool {
    guard let v else { return false }
    return v.x.isFinite && v.y.isFinite && v.z.isFinite
}

/// The radius within which `share` of the points lie (nearest rank).
nonisolated private func percentile(_ out: [String: Vec], _ share: Double = 0.95) -> Double {
    let r = out.values.map(length).sorted()
    return r[max(0, Int((Double(r.count) * share).rounded(.up)) - 1)]
}

nonisolated private func reversed(_ g: VisibleBrainGraph) -> VisibleBrainGraph {
    VisibleBrainGraph(nodes: g.nodes.reversed(), edges: g.edges.reversed(), index: g.index)
}

nonisolated private func same(_ a: [String: Vec], _ b: [String: Vec]) -> Bool {
    a.count == b.count && a.allSatisfy { b[$0.key] == $0.value }
}

nonisolated private func sample() -> VisibleBrainGraph {
    build(
        [
            node("m1", .memory, pos: (3, 0, 0)),
            node("m2", .memory, pos: (0, -1.5, 0)),
            node("m3", .memory, pos: (1, 1, 1)),
            node("n1", .note),
            node("n2", .note),
            node("lonely", .note),
            node("also-lonely", .memory),
            node("tag:go", .tag),
        ],
        [
            edge("m1", "tag:go", .tag),
            edge("m2", "tag:go", .tag),
            edge("n1", "m3", .source),
            edge("n2", "n1", .link),
        ]
    )
}

/// A small vault: three separate groups, no server positions at all.
nonisolated private func threeParts() -> VisibleBrainGraph {
    var nodes: [BrainGraphNodeDTO] = []
    var edges: [BrainGraphEdgeDTO] = []
    func part(_ prefix: String, _ size: Int) {
        for i in 0 ..< size { nodes.append(node("\(prefix)\(i)", .note)) }
        for i in 1 ..< size { edges.append(edge("\(prefix)\(i)", "\(prefix)\((i - 1) / 2)", .link)) }
    }
    part("a", 10)
    part("b", 7)
    part("c", 4)
    nodes.append(node("lonely", .note))
    return build(nodes, edges)
}

struct ConstellationPositionsTests {
    @Test func keepsTheDirectionOfAMemoryWithAPosition() {
        let out = positions(sample())
        let m1 = at(out, "m1"), m3 = at(out, "m3")
        #expect(m1.x > 0)
        #expect(abs(m1.y) / length(m1) < 1e-9)
        #expect(abs(m1.z) / length(m1) < 1e-9)
        let unit = 1 / 3.0.squareRoot()
        #expect(abs(m3.x / length(m3) - unit) < 0.005)
        #expect(abs(m3.y / length(m3) - unit) < 0.005)
        #expect(abs(m3.z / length(m3) - unit) < 0.005)
    }

    @Test func scalesAFreshLayoutSo95PercentLieWithinTheCloudRadius() {
        #expect(abs(percentile(positions(sample())) - cloudRadius) < 0.005)
        #expect(abs(percentile(positions(threeParts())) - cloudRadius) < 0.005)
    }

    @Test func keepsALinkedPairCloserThanAnUnlinkedPair() {
        let out = positions(threeParts())
        #expect(distance(at(out, "a1"), at(out, "a0")) < distance(at(out, "a9"), at(out, "c3")))
    }

    @Test func keepsSeparateGroupsAndAnUnlinkedPointNearTheCloud() {
        let out = positions(threeParts())
        for p in out.values { #expect(length(p) < cloudRadius * 1.5) }
        // The groups do not sit on top of each other either.
        func centre(_ prefix: String, _ size: Int) -> Vec {
            (0 ..< size).reduce(Vec.zero) { $0 + at(out, "\(prefix)\($1)") / Double(size) }
        }
        #expect(distance(centre("a", 10), centre("b", 7)) > 10)
    }

    @Test func makesAGenuine3DStructureWhenNothingHasAPosition() {
        let out = positions(threeParts())
        for axis in 0 ..< 3 {
            let v = out.values.map { $0[axis] }
            let mean = v.reduce(0, +) / Double(v.count)
            let sd = (v.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(v.count)).squareRoot()
            #expect(sd > 10)
        }
    }

    @Test func givesTheSameOutputForTheSameInput() {
        #expect(same(positions(sample()), positions(sample())))
        #expect(same(positions(threeParts()), positions(threeParts())))
    }

    @Test func doesNotDependOnTheOrderTheNodesAndEdgesArriveIn() {
        for g in [sample(), threeParts()] {
            let a = positions(g)
            let b = positions(reversed(g))
            for (id, p) in a { #expect(b[id] == p) }
        }
    }

    @Test func givesEveryVisibleIDAFinitePosition() {
        for g in [sample(), threeParts()] {
            let out = positions(g)
            #expect(out.count == g.nodes.count)
            for n in g.nodes { #expect(finite(out[n.id])) }
        }
    }

    @Test func leavesPriorPositionsExactlyWhereTheyWereAndMovesOnlyNewIDs() {
        let g = threeParts()
        var prior = positions(g)
        prior["c3"] = nil
        let second = ConstellationLayout.layoutConstellation(g, prior: prior, scale: nil, spacing: 20)
        #expect(second.normalised == false)
        for (id, p) in prior { #expect(second.positions[id] == p) }
        #expect(finite(second.positions["c3"]))
    }

    @Test func handlesAnEmptyGraphAndASingleMemoryAtTheOrigin() {
        #expect(positions(build([], [])).isEmpty)
        let out = positions(build([node("m", .memory, pos: (0, 0, 0))], []))
        #expect(out["m"] == Vec.zero)
        let single = positions(build([node("n", .note)], []))
        #expect(finite(single["n"]))
    }

    @Test func spendsFewerTicksOnALargeGraphAndSpacesASmallOneWider() {
        #expect(ConstellationLayout.tickBudget(400) == 300)
        #expect(ConstellationLayout.tickBudget(2000) < 300)
        #expect(ConstellationLayout.tickBudget(2000) >= 80)
        #expect(ConstellationLayout.naturalSpacing(22) > ConstellationLayout.naturalSpacing(2000))
    }
}

nonisolated private let v1 = UUID(uuid: (0xAA, 0xAA, 0xAA, 0xAA, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
nonisolated private let v2 = UUID(uuid: (0xBB, 0xBB, 0xBB, 0xBB, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))

/// Memories in two vaults (the farthest in V2), notes and a tag hub.
nonisolated private func world() -> (nodes: [BrainGraphNodeDTO], edges: [BrainGraphEdgeDTO]) {
    (
        [
            node("m1", .memory, vault: v1, pos: (1, 0, 0)),
            node("m2", .memory, vault: v1, pos: (0, 1, 0)),
            node("m3", .memory, vault: v1, pos: (0, 0, -1)),
            node("far", .memory, vault: v2, pos: (4, 4, 0)),
            node("n1", .note, vault: v1),
            node("n2", .note, vault: v1),
            node("n3", .note, vault: v2),
            node("tag:go", .tag),
        ],
        [
            edge("n1", "m1", .source),
            edge("n1", "tag:go", .tag),
            edge("n2", "tag:go", .tag),
            edge("n3", "tag:go", .tag),
            edge("n2", "m2", .link),
        ]
    )
}

nonisolated private func filters(vaults: Set<UUID>? = nil, tagsOff: Bool = false) -> BrainGraphFilters {
    var f = BrainGraphModel.defaultFilters()
    f.vaults = vaults
    if tagsOff { f.links[.tag] = false }
    return f
}

struct ConstellationMemoryTests {
    @Test func leavesEveryOtherPointWhereItWasWhenTheFarthestMemoryIsHidden() {
        let (nodes, edges) = world()
        var memory = ConstellationLayout()
        let before = memory.place(build(nodes, edges))
        #expect(memory.fresh)
        let after = memory.place(build(nodes, edges, filters(vaults: [v1])))
        #expect(!memory.fresh)
        #expect(after["far"] == nil)
        for (id, p) in after { #expect(p == before[id]) }
    }

    @Test func restoresEveryPositionExactlyWhenAHubKindIsToggledOffAndOn() {
        let (nodes, edges) = world()
        var memory = ConstellationLayout()
        let before = memory.place(build(nodes, edges))
        let noTags = memory.place(build(nodes, edges, filters(tagsOff: true)))
        #expect(noTags["tag:go"] == nil)
        for (id, p) in noTags { #expect(p == before[id]) }
        let back = memory.place(build(nodes, edges))
        #expect(same(back, before))
    }

    @Test func placesANewcomerNearItsPlacedNeighbourAndMovesNobodyElse() {
        let (nodes, edges) = world()
        var memory = ConstellationLayout()
        let before = memory.place(build(nodes, edges))
        let after = memory.place(build(
            nodes + [node("late", .note, vault: v1), node("alone", .note)],
            edges + [edge("late", "m3", .link)]
        ))
        #expect(!memory.fresh)
        #expect(memory.grew)
        for (id, p) in before { #expect(after[id] == p) }
        let late = at(after, "late")
        let toM3 = distance(late, at(before, "m3"))
        for (id, p) in before where id != "m3" { #expect(toM3 < distance(late, p)) }
        #expect(length(at(after, "alone")) < cloudRadius * 1.5)
    }

    @Test func keepsTheScaleFixedAtTheFreshGraph() {
        let (nodes, edges) = world()
        var memory = ConstellationLayout()
        let small = nodes.filter { $0.id != "far" }
        let before = memory.place(build(small, edges))
        let after = memory.place(build(nodes, edges))
        for (id, p) in before { #expect(after[id] == p) }
        // The newcomer is beyond the fixed scale, so it is pulled in to the cloud's edge.
        #expect(length(at(after, "far")) <= cloudRadius + 1e-9)
    }

    @Test func startsAfreshWhenEveryIDIsNew() {
        var memory = ConstellationLayout()
        _ = memory.place(build([node("a", .memory, pos: (1, 0, 0))], []))
        let next = memory.place(build([node("b", .memory, pos: (0, 2, 0))], []))
        #expect(memory.fresh)
        #expect(abs(at(next, "b").y - cloudRadius) < 0.005)
    }

    @Test func laysADisjointVaultShownAloneOutAfreshAndKeepsItWhenBothAreShown() {
        // A vault filter shows vault A only; a switch to vault B alone shows
        // nothing seen before, so it starts a new sky (A is forgotten); then
        // every vault is shown, half of it known, so B stays put.
        var nodes: [BrainGraphNodeDTO] = []
        var edges: [BrainGraphEdgeDTO] = []
        for (v, p) in [(v1, "a"), (v2, "b")] {
            for i in 0 ..< 12 { nodes.append(node("\(p)\(i)", .note, vault: v)) }
            for i in 1 ..< 12 { edges.append(edge("\(p)\(i)", "\(p)\((i - 1) / 2)", .link)) }
        }
        var memory = ConstellationLayout()
        let onlyA = memory.place(build(nodes, edges, filters(vaults: [v1])))
        let onlyB = memory.place(build(nodes, edges, filters(vaults: [v2])))
        // Nothing on screen was seen before, so the renderer frames it afresh.
        #expect(memory.fresh)
        for p in onlyB.values {
            #expect(finite(p))
            #expect(length(p) < cloudRadius * 1.5)
        }
        #expect(onlyA.count == 12)
        let both = memory.place(build(nodes, edges))
        #expect(!memory.fresh)
        #expect(memory.grew)
        for (id, p) in onlyB { #expect(both[id] == p) }
        for p in both.values { #expect(length(p) < cloudRadius * 1.5) }
    }
}

/// A vault of `count` notes in a tree (three children each), ids `prefix + i`.
nonisolated private func tree(_ count: Int, _ prefix: String) -> (nodes: [BrainGraphNodeDTO], edges: [BrainGraphEdgeDTO]) {
    let nodes = (0 ..< count).map { node("\(prefix)\($0)", .note) }
    let edges = (1 ..< count).map { edge("\(prefix)\($0)", "\(prefix)\(($0 - 1) / 3)", .link) }
    return (nodes, edges)
}

/// The graph made of the given nodes and the edges between them.
nonisolated private func subgraph(_ nodes: [BrainGraphNodeDTO], _ edges: [BrainGraphEdgeDTO]) -> VisibleBrainGraph {
    let ids = Set(nodes.map(\.id))
    return build(nodes, edges.filter { ids.contains($0.from) && ids.contains($0.to) })
}

struct ConstellationMemoryMostlyNewTests {
    private func near(_ r: Double) -> Double { abs(r - cloudRadius) / cloudRadius }

    @Test func laysALargeGraphOutAfreshAfterASmallOneItContains() {
        // "Show in graph" on one note, then "Full graph".
        let (nodes, edges) = tree(800, "s")
        var memory = ConstellationLayout()
        _ = memory.place(subgraph(Array(nodes.prefix(6)), edges))
        let full = memory.place(build(nodes, edges))
        #expect(near(percentile(full)) < 0.15)
        #expect(memory.fresh)
    }

    @Test func laysALargeDisjointVaultOutAfreshAfterASmallOne() {
        let a = tree(15, "a")
        let b = tree(800, "b")
        var memory = ConstellationLayout()
        _ = memory.place(build(a.nodes, a.edges))
        let out = memory.place(build(b.nodes, b.edges))
        #expect(near(percentile(out)) < 0.15)
        #expect(memory.fresh)
    }

    @Test func stillRestoresEveryPositionWhenAFilterHides30PercentAndShowsItAgain() {
        let (nodes, edges) = tree(800, "s")
        var memory = ConstellationLayout()
        let before = memory.place(build(nodes, edges))
        let shown = nodes.enumerated().filter { $0.offset % 10 >= 3 }.map(\.element)
        let hidden = memory.place(subgraph(shown, edges))
        #expect(!memory.fresh)
        for (id, p) in hidden { #expect(p == before[id]) }
        let back = memory.place(build(nodes, edges))
        #expect(!memory.fresh)
        #expect(same(back, before))
    }

    @Test func movesNoKnownIDWhen10PercentNewcomersArrive() {
        let (nodes, edges) = tree(880, "s")
        var memory = ConstellationLayout()
        let before = memory.place(subgraph(Array(nodes.prefix(800)), edges))
        let after = memory.place(build(nodes, edges))
        #expect(!memory.fresh)
        #expect(memory.grew)
        for (id, p) in before { #expect(after[id] == p) }
    }
}

/// `count` notes with no links at all, ids `prefix + i`, after `extra`.
nonisolated private func unlinked(_ count: Int, _ prefix: String, _ extra: [String] = []) -> VisibleBrainGraph {
    build((extra + (0 ..< count).map { "\(prefix)\($0)" }).map { node($0, .note) }, [])
}

struct ConstellationRepulsionTests {
    // These two ids share an FNV-1a hash, so every hashed placement puts them
    // on exactly the same spot.
    private static let sameSpot = ["star-836998", "star-1037286"]
    // These two start about a thousandth of a link length apart.
    private static let nearSpot = ["near-61991", "near-50099"]

    @Test func theCoincidentIDsReallyShareAHash() {
        #expect(BrainIDHash.hashID(Self.sameSpot[0]) == BrainIDHash.hashID(Self.sameSpot[1]))
    }

    @Test func partsTwoCoincidentStartingPointsWithoutFlingingThemOutOfTheCloud() {
        let out = positions(unlinked(48, "dot-", Self.sameSpot))
        for p in out.values { #expect(length(p) < cloudRadius * 1.5) }
        #expect(distance(at(out, Self.sameSpot[0]), at(out, Self.sameSpot[1])) > 1)
    }

    @Test func partsTwoNearCoincidentStartingPointsWithoutFlingingThemOutOfTheCloud() {
        let out = positions(unlinked(48, "dot-", Self.nearSpot))
        for p in out.values { #expect(length(p) < cloudRadius * 1.5) }
        #expect(distance(at(out, Self.nearSpot[0]), at(out, Self.nearSpot[1])) > 1)
    }

    @Test func keepsEveryOneOf2000UnlinkedPointsWithin1Point5TimesTheCloudRadius() {
        let out = positions(unlinked(2000, "n"))
        #expect(out.values.allSatisfy { length($0) < cloudRadius * 1.5 })
    }
}

/// A small LCG, so the generated graphs are the same on every run.
nonisolated private struct LCG {
    var s: UInt32
    mutating func next() -> Double {
        s = s &* 1_664_525 &+ 1_013_904_223
        return Double(s) / 4_294_967_296
    }
}

/// The owner's own vault: every note has the same author, and about a third
/// also carry one of nine tags. 2,000 points in all.
nonisolated private func singleAuthor() -> (graph: VisibleBrainGraph, tagOf: [String: Int]) {
    var rnd = LCG(s: 7)
    var nodes = [node("author:me", .author)]
    var edges: [BrainGraphEdgeDTO] = []
    var tagOf: [String: Int] = [:]
    for k in 0 ..< 9 { nodes.append(node("tag:\(k)", .tag)) }
    for i in 0 ..< 1990 {
        let id = "note-\(i)"
        nodes.append(node(id, .note))
        edges.append(edge(id, "author:me", .author))
        if rnd.next() < 0.3 {
            let k = Int(rnd.next() * 9)
            tagOf[id] = k
            edges.append(edge(id, "tag:\(k)", .tag))
        }
    }
    return (build(nodes, edges), tagOf)
}

/// One run of the 2,000-point vault, shared by the tests that only read it.
nonisolated private let singleAuthorRun: (graph: VisibleBrainGraph, tagOf: [String: Int], result: ConstellationLayout.Result) = {
    let (graph, tagOf) = singleAuthor()
    return (graph, tagOf, ConstellationLayout.layoutConstellation(graph))
}()

struct ConstellationLayoutQualityTests {
    @Test func laysOutASmallThreePartVaultWithLinkedStarsCloseAndNoTwoOnTopOfEachOther() {
        let g = threeParts()
        let out = positions(g)
        var linked = Set<String>()
        for e in g.edges {
            linked.insert("\(e.from)|\(e.to)")
            linked.insert("\(e.to)|\(e.from)")
        }
        let ids = Array(out.keys)
        var near = 0.0, nearCount = 0.0, far = 0.0, farCount = 0.0
        var closest = Double.infinity
        for i in ids.indices {
            for j in (i + 1) ..< ids.count {
                let d = distance(at(out, ids[i]), at(out, ids[j]))
                closest = min(closest, d)
                if linked.contains("\(ids[i])|\(ids[j])") {
                    near += d
                    nearCount += 1
                } else {
                    far += d
                    farCount += 1
                }
            }
        }
        #expect(near / nearCount < (far / farCount) * 0.75)
        // 22 stars fill a cloud of radius 100 about 57 apart on average; closer
        // than 15, two stars and their labels run into each other.
        #expect(closest > 15)
        for p in out.values { #expect(length(p) < cloudRadius * 1.5) }
    }

    @Test func spreadsASingleAuthorsNotesThroughAVolumeAroundTheHubWithTagsAsClusters() {
        let (_, tagOf, result) = singleAuthorRun
        let out = result.positions
        let hub = at(out, "author:me")
        let r = (0 ..< 1990).map { distance(at(out, "note-\($0)"), hub) }
        let mean = r.reduce(0, +) / Double(r.count)
        let sd = (r.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(r.count)).squareRoot()
        // Not a tight ball crushed onto the hub: the author links rest at 0.7
        // link lengths; a volume that gives each note room sits at several.
        #expect(mean > result.spacing * 2)
        // Not a hollow shell either: uniform in a ball gives sd/mean = 0.26.
        #expect(sd / mean > 0.15)
        // Notes that share a tag sit closer to each other than to the rest.
        var same = 0.0, sameCount = 0.0, other = 0.0, otherCount = 0.0
        // The web walks a Map in insertion order; this is the same order.
        let tagged = (0 ..< 1990).map { "note-\($0)" }.filter { tagOf[$0] != nil }
        for i in stride(from: 0, to: tagged.count, by: 3) {
            for j in stride(from: 0, to: 1990, by: 7) {
                let b = "note-\(j)"
                if b == tagged[i] { continue }
                let d = distance(at(out, tagged[i]), at(out, b))
                if tagOf[b] == tagOf[tagged[i]] {
                    same += d
                    sameCount += 1
                } else {
                    other += d
                    otherCount += 1
                }
            }
        }
        #expect(same / sameCount < (other / otherCount) * 0.75)
    }
}

struct ConstellationDeterminismTests {
    /// A big hub, a dense cluster of pinned memories, and notes linked to both.
    private func crowded() -> VisibleBrainGraph {
        var rnd = LCG(s: 3)
        var nodes = [node("tag:big", .tag)]
        var edges: [BrainGraphEdgeDTO] = []
        for i in 0 ..< 120 {
            let x = 1 + rnd.next() * 0.01, y = rnd.next() * 0.01, z = rnd.next() * 0.01
            nodes.append(node("m\(i)", .memory, pos: (x, y, z)))
        }
        for i in 0 ..< 400 {
            nodes.append(node("n\(i)", .note))
            edges.append(edge("n\(i)", "tag:big", .tag))
            if i.isMultiple(of: 4) { edges.append(edge("n\(i)", "m\(i % 120)", .source)) }
        }
        return build(nodes, edges)
    }

    @Test func givesBitIdenticalOutputForAnyInputOrderFreshAndIncremental() {
        let g = crowded()
        let r = reversed(g)
        let a = ConstellationLayout.layoutConstellation(g)
        let b = ConstellationLayout.layoutConstellation(r)
        #expect(same(b.positions, a.positions))
        var prior = a.positions
        for i in stride(from: 0, to: 400, by: 37) { prior["n\(i)"] = nil }
        let c = ConstellationLayout.layoutConstellation(g, prior: prior, scale: a.scale, spacing: a.spacing)
        let d = ConstellationLayout.layoutConstellation(r, prior: prior, scale: a.scale, spacing: a.spacing)
        #expect(same(d.positions, c.positions))
        for (id, p) in prior { #expect(c.positions[id] == p) }
        for p in c.positions.values { #expect(finite(p)) }
    }
}

struct ConstellationLayoutCostTests {
    // Counted, not timed: a return of the quadratic cost shows up as pair
    // visits or simulated bodies whatever the machine.
    @Test func visitsAtMost150PairsPerFreePointPerTickOnA2000PointSingleAuthorVault() {
        let cost = singleAuthorRun.result.cost
        #expect(cost.bodies == 2000)
        #expect(cost.ticks > 0)
        #expect(Double(cost.pairVisits) / Double(cost.bodies * cost.ticks) <= 150)
    }

    @Test func simulatesFewerThan100BodiesToPlace9NewcomersAmong2000PointsMovingNobodyElse() {
        let (graph, _, first) = singleAuthorRun
        var prior = first.positions
        for i in 0 ..< 9 { prior["note-\(i * 211)"] = nil }
        let next = ConstellationLayout.layoutConstellation(graph, prior: prior, scale: first.scale, spacing: first.spacing)
        #expect(next.cost.bodies < 100)
        for (id, p) in prior { #expect(next.positions[id] == p) }
        for i in 0 ..< 9 { #expect(finite(next.positions["note-\(i * 211)"])) }
    }
}

struct ConstellationNewcomerTests {
    @Test func strandsNoneOf300NewcomersBeyond1Point5TimesTheCloudRadius() {
        var worst = 0.0
        for seed: UInt32 in [1, 2, 3, 4, 5, 6] {
            var rnd = LCG(s: seed)
            var nodes: [BrainGraphNodeDTO] = []
            // Five tight clumps of 240 memories each.
            for i in 0 ..< 1200 {
                let c = Double(i % 5)
                let x = cos(c) + rnd.next() * 0.02
                let y = sin(c) + rnd.next() * 0.02
                let z = (c - 2) / 3 + rnd.next() * 0.02
                nodes.append(node("m\(i)", .memory, pos: (x, y, z)))
            }
            var memory = ConstellationLayout()
            _ = memory.place(build(nodes, []))
            var edges: [BrainGraphEdgeDTO] = []
            var more = nodes
            for i in 0 ..< 300 {
                more.append(node("n\(i)", .note))
                edges.append(edge("n\(i)", "m\(Int(rnd.next() * 1200))", .source))
            }
            let out = memory.place(build(more, edges))
            #expect(!memory.fresh)
            for i in 0 ..< 300 { worst = max(worst, length(at(out, "n\(i)"))) }
        }
        #expect(worst <= cloudRadius * 1.5)
    }
}

struct ConstellationMemoryScaleTests {
    private func mem(_ id: String, _ x: Double, _ y: Double, _ z: Double) -> BrainGraphNodeDTO {
        node(id, .memory, pos: (x, y, z))
    }

    private func finiteInCloud(_ out: [String: Vec]) {
        for p in out.values {
            #expect(finite(p))
            #expect(length(p) <= cloudRadius + 1e-9)
        }
    }

    @Test func handlesIdenticalPositions() {
        let out = positions(build([mem("a", 2, 2, 2), mem("b", 2, 2, 2), mem("c", 2, 2, 2)], []))
        finiteInCloud(out)
        #expect(abs(length(at(out, "a")) - cloudRadius) < 0.005)
    }

    @Test func handlesAllZeroPositionsNoScaleEveryMemoryAtTheOrigin() {
        let g = build([mem("a", 0, 0, 0), mem("b", 0, 0, 0)], [])
        #expect(ConstellationLayout.memoryScale(g.nodes) == nil)
        let out = positions(g)
        finiteInCloud(out)
        #expect(out["a"] == Vec.zero)
    }

    @Test func handlesHugeAndTinyPositions() {
        let outHuge = positions(build([mem("a", 1e300, 0, 0), mem("b", 0, -1e300, 0)], []))
        finiteInCloud(outHuge)
        #expect(abs(at(outHuge, "a").x - cloudRadius) < 0.005)
        let outTiny = positions(build([mem("a", 1e-6, 0, 0), mem("b", 0, 2e-6, 0)], []))
        finiteInCloud(outTiny)
        #expect(abs(at(outTiny, "b").y - cloudRadius) < 0.005)
        #expect(abs(at(outTiny, "a").x - cloudRadius / 2) < 0.005)
        let vanishing = build([mem("a", 1e-12, 0, 0)], [])
        #expect(ConstellationLayout.memoryScale(vanishing.nodes) == nil)
        finiteInCloud(positions(vanishing))
    }

    @Test func doesNotLetOneFarOutlierCollapseTheRest() {
        var nodes = (0 ..< 40).map { i in mem("m\(i)", cos(Double(i)), sin(Double(i)), Double(i % 5) / 5) }
        nodes.append(mem("outlier", 1000, 0, 0))
        let out = positions(build(nodes, []))
        finiteInCloud(out)
        // The bulk still fills the cloud, and the outlier sits on its edge.
        let bulk = (0 ..< 40).map { length(at(out, "m\($0)")) }.max() ?? 0
        #expect(bulk > cloudRadius * 0.9)
        #expect(abs(length(at(out, "outlier")) - cloudRadius) < 0.005)
    }
}

/// The renderer's entry point: the memory's positions as Float, and its fresh flag.
struct ConstellationLayoutEntryPointTests {
    @Test func layoutIsPlaceAsFloatWithTheFreshFlag() {
        let (nodes, edges) = world()
        var a = ConstellationLayout()
        var b = ConstellationLayout()
        let exact = a.place(build(nodes, edges))
        let shown = b.layout(build(nodes, edges))
        #expect(shown.fresh)
        #expect(shown.positions.count == exact.count)
        for (id, p) in exact { #expect(shown.positions[id] == SIMD3<Float>(p)) }
        let again = b.layout(build(nodes, edges, filters(vaults: [v1])))
        #expect(!again.fresh)
    }
}
