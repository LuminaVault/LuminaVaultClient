// Port of the web app's graph-model.test.ts: same graph, same cases.

import Foundation
@testable import LuminaVaultClient
import LuminaVaultShared
import Testing

struct BrainGraphModelTests {
    private static let v1 = UUID(uuid: (0xAA, 0xAA, 0xAA, 0xAA, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 1))
    private static let v2 = UUID(uuid: (0xBB, 0xBB, 0xBB, 0xBB, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 2))
    private static let s1 = UUID(uuid: (0xCC, 0xCC, 0xCC, 0xCC, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 3))
    private static let spaceHub = "space:\(s1.uuidString)"

    private static func node(
        _ id: String, _ kind: BrainNodeKindDTO, _ label: String,
        vault: UUID? = nil, space: UUID? = nil
    ) -> BrainGraphNodeDTO {
        BrainGraphNodeDTO(id: id, kind: kind, label: label, vaultID: vault, spaceID: space, weight: 0)
    }

    private static func edge(_ from: String, _ to: String, _ kind: BrainLinkKindDTO) -> BrainGraphEdgeDTO {
        BrainGraphEdgeDTO(from: from, to: to, kind: kind)
    }

    private static func response(
        nodes: [BrainGraphNodeDTO], edges: [BrainGraphEdgeDTO]
    ) -> BrainGraphResponse {
        BrainGraphResponse(
            generatedAt: Date(timeIntervalSince1970: 0),
            vaults: [
                BrainGraphVaultDTO(id: v1, name: "Personal", personal: true),
                BrainGraphVaultDTO(id: v2, name: "Work", personal: false),
            ],
            nodes: nodes, edges: edges
        )
    }

    private static let graph = response(
        nodes: [
            node("n1", .note, "Go notes", vault: v1, space: s1),
            node("n2", .note, "Linked note", vault: v1, space: s1),
            node("n3", .note, "Work go", vault: v2),
            node("orphan", .note, "Lonely", vault: v1),
            node("m1", .memory, "A memory", vault: v1),
            node("tag:go", .tag, "go"),
            node(spaceHub, .space, "Space one", vault: v1),
            node("author:user:U1", .author, "Me"),
        ],
        edges: [
            edge("n1", "n2", .link),
            edge("n1", "tag:go", .tag),
            edge("n3", "tag:go", .tag),
            edge("n1", spaceHub, .space),
            edge("n2", spaceHub, .space),
            edge("m1", "n1", .source),
            edge("n1", "author:user:U1", .author),
            edge("m1", "author:user:U1", .author),
            edge("n1", "ghost", .link),
        ]
    )

    private func ids(_ nodes: [BrainGraphNodeDTO]) -> [String] { nodes.map(\.id).sorted() }

    private func filters(
        links off: [BrainLinkKindDTO] = [], vaults: Set<UUID>? = nil,
        showOrphans: Bool = true, colourBy: BrainColourBy = .vault
    ) -> BrainGraphFilters {
        var f = BrainGraphModel.defaultFilters()
        for k in off { f.links[k] = false }
        f.vaults = vaults
        f.showOrphans = showOrphans
        f.colourBy = colourBy
        return f
    }

    private func get(_ index: BrainGraphIndex, _ id: String) throws -> BrainGraphNodeDTO {
        try #require(index.byID[id])
    }

    private func visible(_ g: BrainGraphResponse = BrainGraphModelTests.graph, _ f: BrainGraphFilters? = nil)
        -> VisibleBrainGraph
    {
        BrainGraphModel.visible(g, filters: f ?? filters())
    }

    // MARK: defaultFilters

    @Test func defaultFiltersHaveEveryLinkKindOnExceptSimilar() {
        let f = BrainGraphModel.defaultFilters()
        #expect(f.links == [
            .link: true, .source: true, .tag: true, .author: true,
            .entity: true, .space: true, .similar: false,
        ])
        #expect(f.vaults == nil)
        #expect(f.showOrphans)
        #expect(f.colourBy == .vault)
    }

    // MARK: visible

    @Test func keepsEverythingAttachedByDefaultAndDropsEdgesWithAMissingEndpoint() {
        let v = visible()
        #expect(ids(v.nodes).contains("tag:go"))
        #expect(!v.edges.contains { $0.to == "ghost" })
        for e in v.edges {
            #expect(v.index.byID[e.from] != nil)
            #expect(v.index.byID[e.to] != nil)
        }
    }

    @Test func removesAHubKindAndItsEdgesWhenToggledOffKeepingMembers() {
        let v = visible(Self.graph, filters(links: [.tag]))
        #expect(v.index.byID["tag:go"] == nil)
        #expect(!v.edges.contains { $0.kind == .tag })
        #expect(v.index.byID["n1"] != nil)
        #expect(v.index.byID["n3"] != nil)
    }

    @Test func dropsANonHubEdgeKindButKeepsItsEndpoints() {
        let v = visible(Self.graph, filters(links: [.link]))
        #expect(!v.edges.contains { $0.kind == .link })
        #expect(v.index.byID["n2"] != nil)
    }

    @Test func restrictingToOneVaultDropsTheOtherVaultAndTheHubLeftWithOneMember() {
        let v = visible(Self.graph, filters(vaults: [Self.v1]))
        #expect(v.index.byID["n3"] == nil)
        #expect(v.index.byID["tag:go"] == nil)
        #expect(v.index.byID["n1"] != nil)
        #expect(v.index.byID[Self.spaceHub] != nil)
    }

    // Web case "matches vault ids in either case": vault ids are UUID values here,
    // so case cannot arise. The equivalent is that a UUID parsed from lowercase
    // text selects the same vault.
    @Test func matchesVaultIDsParsedFromEitherCase() throws {
        let lower = try #require(UUID(uuidString: Self.v1.uuidString.lowercased()))
        let v = visible(Self.graph, filters(vaults: [lower]))
        #expect(v.index.byID["n1"] != nil)
        #expect(v.index.byID["n3"] == nil)
    }

    @Test func dropsSpaceHubsWhoseVaultIsNotSelected() {
        let v = visible(Self.graph, filters(vaults: [Self.v2]))
        #expect(v.index.byID[Self.spaceHub] == nil)
        #expect(v.index.byID["n1"] == nil)
    }

    @Test func dropsHubsWithFewerThanTwoMembers() {
        let g = Self.response(
            nodes: Self.graph.nodes + [Self.node("tag:solo", .tag, "solo")],
            edges: Self.graph.edges + [Self.edge("n2", "tag:solo", .tag)]
        )
        let v = visible(g)
        #expect(v.index.byID["tag:solo"] == nil)
        #expect(!v.edges.contains { $0.to == "tag:solo" })
    }

    @Test func showOrphansFalseRemovesUnconnectedNotesAndKeepsLinkedOnes() {
        #expect(visible().index.byID["orphan"] != nil)
        let v = visible(Self.graph, filters(showOrphans: false))
        #expect(v.index.byID["orphan"] == nil)
        #expect(v.index.byID["n1"] != nil)
    }

    @Test func turningAToggleOffCanOrphanANoteWhichShowOrphansFalseThenRemoves() {
        let g = Self.response(nodes: Self.graph.nodes, edges: [Self.edge("m1", "n1", .source)])
        let v = visible(g, filters(links: [.source], showOrphans: false))
        #expect(v.nodes.filter { !BrainGraphModel.isHub($0) }.isEmpty)
    }

    // Web "does not mutate its input and returns new arrays": value types make
    // mutation impossible; the observable part is that the input is unchanged
    // and the output is a filtered copy.
    @Test func doesNotChangeItsInputAndReturnsFilteredCopies() {
        let nodes = Self.graph.nodes
        let edges = Self.graph.edges
        let v = visible(Self.graph, filters(showOrphans: false))
        #expect(Self.graph.nodes == nodes)
        #expect(Self.graph.edges == edges)
        #expect(v.nodes.count < nodes.count)
        #expect(v.edges.count < edges.count)
    }

    @Test func buildsNeighboursAndEdgesOfFromWhatIsLeft() {
        let v = visible()
        #expect(v.index.neighbours["n2"] == ["n1", Self.spaceHub])
        #expect(v.index.edgesOf["n2"]?.count == 2)
    }

    @Test func filters2000NodesWithinTheTimingBudget() {
        var nodes = [Self.node("tag:big", .tag, "big")]
        var edges: [BrainGraphEdgeDTO] = []
        for i in 0 ..< 2000 {
            nodes.append(Self.node("n\(i)", i % 2 == 1 ? .note : .memory, "Item \(i)", vault: Self.v1))
            edges.append(Self.edge("n\(i)", "tag:big", .tag))
            if i > 0 { edges.append(Self.edge("n\(i)", "n\(i - 1)", .link)) }
        }
        let big = Self.response(nodes: nodes, edges: edges)
        _ = visible(big)
        let f = filters(vaults: [Self.v1], showOrphans: false)
        let start = ContinuousClock.now
        let v = visible(big, f)
        let elapsed = ContinuousClock.now - start
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        print("visible() on 2000 nodes: \(ms) ms")
        #expect(v.nodes.count == 2001)
        #if DEBUG
        #expect(ms < 300)
        #else
        #expect(ms < 30)
        #endif
    }

    // MARK: litSet

    @Test func litSetReturnsTheIDsPlusTheirNeighboursAndNothingElse() {
        let index = visible().index
        #expect(BrainGraphModel.litSet(index, ids: ["n2"]) == ["n1", "n2", Self.spaceHub])
    }

    @Test func litSetUnionsSeveralIDsAndIgnoresUnknownOnes() {
        let index = visible().index
        #expect(BrainGraphModel.litSet(index, ids: ["m1", "nope"]) == ["author:user:U1", "m1", "n1"])
    }

    // MARK: groupMembers

    @Test func groupMembersReturnsTheItemsAttachedToAHub() {
        let index = visible().index
        #expect(BrainGraphModel.groupMembers(index, hubID: "tag:go").sorted() == ["n1", "n3"])
    }

    @Test func groupMembersReturnsAnEmptyListForAnUnknownID() {
        #expect(BrainGraphModel.groupMembers(visible().index, hubID: "tag:none") == [])
    }

    // MARK: search

    private static let searchNodes = [
        node("1", .note, "Learning Go"),
        node("2", .note, "Go basics"),
        node("3", .note, "Gopher"),
        node("4", .note, "Unrelated"),
    ]

    @Test func searchMatchesCaseInsensitivelyPrefixMatchesFirst() {
        #expect(BrainGraphModel.search(Self.searchNodes, query: "GO").map(\.id) == ["2", "3", "1"])
    }

    @Test func searchIgnoresAnEmptyOrBlankQuery() {
        #expect(BrainGraphModel.search(Self.searchNodes, query: "").isEmpty)
        #expect(BrainGraphModel.search(Self.searchNodes, query: "   ").isEmpty)
    }

    @Test func searchHonoursLimitDefaultEight() {
        #expect(BrainGraphModel.search(Self.searchNodes, query: "go", limit: 2).count == 2)
        let many = (0 ..< 20).map { Self.node("x\($0)", .note, "item \($0)") }
        #expect(BrainGraphModel.search(many, query: "item").count == 8)
    }

    // MARK: colourKey

    @Test func colourKeyVaultIsTheVaultIDForItemsAndHubForHubsWithoutOne() throws {
        let index = visible().index
        #expect(BrainGraphModel.colourKey((try get(index, "n1")), by: .vault, index: index) == Self.v1.uuidString)
        #expect(BrainGraphModel.colourKey((try get(index, "tag:go")), by: .vault, index: index) == "hub")
    }

    @Test func colourKeyKindIsTheNodeKind() throws {
        let index = visible().index
        #expect(BrainGraphModel.colourKey((try get(index, "m1")), by: .kind, index: index) == "memory")
    }

    @Test func colourKeySpaceIsTheSpaceIDOrNone() throws {
        let index = visible().index
        #expect(BrainGraphModel.colourKey((try get(index, "n1")), by: .space, index: index) == Self.s1.uuidString)
        #expect(BrainGraphModel.colourKey((try get(index, "m1")), by: .space, index: index) == "none")
    }

    @Test func colourKeyAuthorIsTheFirstAuthorHubTheItemIsAttachedToOrNone() throws {
        let index = visible().index
        #expect(BrainGraphModel.colourKey((try get(index, "n1")), by: .author, index: index) == "author:user:U1")
        #expect(BrainGraphModel.colourKey((try get(index, "n2")), by: .author, index: index) == "none")
    }

    // MARK: noSimilarFound

    @Test func noSimilarFoundIsTrueOnlyWhenSimilarWasAskedForIsOnAndNoneCameBack() {
        let asked = BrainGraphRequest(similar: true)
        let withSimilar = Self.response(
            nodes: Self.graph.nodes, edges: Self.graph.edges + [Self.edge("n1", "n3", .similar)]
        )
        let none = BrainGraphModel.noSimilarFound
        #expect(none(Self.graph, asked, true))
        #expect(!none(Self.graph, asked, false))
        #expect(!none(Self.graph, BrainGraphRequest(similar: false), true))
        #expect(!none(withSimilar, asked, true))
        #expect(!none(nil, asked, true))
        #expect(!none(Self.graph, nil, true))
    }

    // MARK: colourLegend

    private static func label(_ id: String) -> String? { graph.nodes.first { $0.id == id }?.label }

    @Test func legendListsTheKindsOfNotesAndMemoriesByCountLeavingHubsOut() {
        let r = BrainGraphModel.colourLegend(visible(), by: .kind, labelOf: Self.label)
        #expect(r.keys == [
            BrainLegendKey(key: "note", label: "Note", count: 4),
            BrainLegendKey(key: "memory", label: "Memory", count: 1),
        ])
        #expect(r.more == 0)
    }

    @Test func legendNamesSpacesAndAuthorsAfterTheirHubsCountingItemsOnly() {
        let v = visible()
        #expect(BrainGraphModel.colourLegend(v, by: .space, labelOf: Self.label).keys == [
            BrainLegendKey(key: "none", label: "No Space", count: 3),
            BrainLegendKey(key: Self.s1.uuidString, label: "Space one", count: 2),
        ])
        #expect(BrainGraphModel.colourLegend(v, by: .author, labelOf: Self.label).keys == [
            BrainLegendKey(key: "none", label: "No author", count: 3),
            BrainLegendKey(key: "author:user:U1", label: "Me", count: 2),
        ])
    }

    @Test func legendShowsTheTopEightAndCountsTheRest() {
        let nodes = (0 ..< 11).map { i in
            Self.node("x\(i)", .note, "X\(i)", space: UUID(uuid: (UInt8(i), 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 1)))
        }
        let many = Self.response(nodes: nodes, edges: [])
        let r = BrainGraphModel.colourLegend(visible(many), by: .space, labelOf: { _ in nil })
        #expect(r.keys.count == 8)
        #expect(r.more == 3)
    }

    @Test func legendHasNothingToListForVaults() {
        let r = BrainGraphModel.colourLegend(visible(), by: .vault, labelOf: Self.label)
        #expect(r.keys.isEmpty)
        #expect(r.more == 0)
    }

    // MARK: copy

    @Test func copyMatchesTheWebLabels() {
        #expect(BrainLinkKindDTO.allCases.map(BrainGraphCopy.linkLabel)
            == ["Links", "Sources", "Tags", "Authors", "Mentions", "Spaces", "Similar"])
        #expect([BrainNodeKindDTO.note, .memory, .tag, .author, .entity, .space].map(BrainGraphCopy.nodeKindName)
            == ["Note", "Memory", "Tag", "Author", "Mention", "Space"])
    }
}
