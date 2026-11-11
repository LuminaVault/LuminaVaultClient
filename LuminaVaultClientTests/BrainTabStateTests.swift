// The Brain screen's pure state mapping: which card for which store state and
// filter result, the Filters badge, the status line, the request the
// controls describe, vault chips, focus selection and the list rows.

import Foundation
@testable import LuminaVaultClient
import LuminaVaultShared
import Testing

struct BrainTabStateTests {
    // MARK: fixtures

    private static func vaultID(_ n: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, n))
    }

    private static let v1 = vaultID(1)
    private static let v2 = vaultID(2)
    private static let v3 = vaultID(3)

    private static func node(
        _ id: String, _ kind: BrainNodeKindDTO, vault: UUID? = v1, weight: Int = 0, label: String? = nil
    ) -> BrainGraphNodeDTO {
        BrainGraphNodeDTO(id: id, kind: kind, label: label ?? id, vaultID: vault, weight: weight)
    }

    private static func response(
        nodes: [BrainGraphNodeDTO], edges: [BrainGraphEdgeDTO] = [], truncated: Bool = false
    ) -> BrainGraphResponse {
        BrainGraphResponse(
            generatedAt: Date(timeIntervalSince1970: 1), truncated: truncated,
            vaults: [
                BrainGraphVaultDTO(id: v1, name: "Personal", personal: true),
                BrainGraphVaultDTO(id: v2, name: "Work", personal: false),
            ],
            nodes: nodes, edges: edges
        )
    }

    /// Two notes and a memory, two of them tagged together, one unlinked.
    private static let graph = response(
        nodes: [
            node("A", .note, weight: 3, label: "Alpha"),
            node("B", .memory, vault: v2, weight: 5, label: "Beta"),
            node("C", .note, weight: 1, label: "Gamma"),
            node("tag:x", .tag, vault: nil, weight: 2, label: "x"),
        ],
        edges: [
            BrainGraphEdgeDTO(from: "A", to: "tag:x", kind: .tag),
            BrainGraphEdgeDTO(from: "B", to: "tag:x", kind: .tag),
            BrainGraphEdgeDTO(from: "A", to: "B", kind: .link),
        ]
    )

    private static func visible(
        _ g: BrainGraphResponse = graph, _ filters: BrainGraphFilters = BrainGraphModel.defaultFilters()
    ) -> VisibleBrainGraph {
        BrainGraphModel.visible(g, filters: filters)
    }

    // MARK: card

    @Test func loadingIsTheFirstLoadCard() {
        #expect(BrainTabState.card(state: .loading, request: BrainGraphRequest(), visible: nil) == .firstLoad)
    }

    @Test func aGraphWithItemsIsTheGraph() {
        let card = BrainTabState.card(state: .loaded(Self.graph), request: BrainGraphRequest(), visible: Self.visible())
        #expect(card == .graph)
    }

    @Test func aVaultWithNoNotesIsTheEmptyCardNotASpinner() {
        let empty = Self.response(nodes: [])
        let card = BrainTabState.card(state: .loaded(empty), request: BrainGraphRequest(), visible: Self.visible(empty))
        #expect(card == .empty)
    }

    @Test func hubsAloneAreStillEmpty() {
        let hubsOnly = Self.response(nodes: [Self.node("tag:x", .tag, vault: nil)])
        let card = BrainTabState.card(
            state: .loaded(hubsOnly), request: BrainGraphRequest(), visible: Self.visible(hubsOnly)
        )
        #expect(card == .empty)
    }

    @Test func filtersThatHideEveryItemSayNothingMatches() {
        var filters = BrainGraphModel.defaultFilters()
        filters.showOrphans = false
        let unlinked = Self.response(nodes: [Self.node("A", .note), Self.node("B", .note)])
        let card = BrainTabState.card(
            state: .loaded(unlinked), request: BrainGraphRequest(), visible: Self.visible(unlinked, filters)
        )
        #expect(card == .nothingMatches)
    }

    @Test func failedOffersShowAllVaultsOnlyWhenTheRequestNamedVaults() {
        let plain = BrainTabState.card(state: .failed("Nope"), request: BrainGraphRequest(), visible: nil)
        #expect(plain == .failed(message: "Nope", showAllVaults: false))
        let named = BrainTabState.card(
            state: .failed("Nope"), request: BrainGraphRequest(vaults: [Self.v1]), visible: nil
        )
        #expect(named == .failed(message: "Nope", showAllVaults: true))
        let emptyList = BrainTabState.card(
            state: .failed("Nope"), request: BrainGraphRequest(vaults: []), visible: nil
        )
        #expect(emptyList == .failed(message: "Nope", showAllVaults: false))
    }

    @Test func missingFocusIsItsOwnCard() {
        #expect(BrainTabState.card(state: .missingFocus, request: BrainGraphRequest(focus: "X"), visible: nil) == .missingFocus)
    }

    @Test func cardCopyMatchesThePlan() {
        #expect(BrainTabState.firstLoadText == "Mapping your notes…")
        #expect(BrainTabState.emptyHeadline == "Nothing to map yet")
        #expect(BrainTabState.missingFocusText == "That is no longer in your graph. It may have been deleted.")
        #expect(BrainTabState.showFullGraphTitle == "Show full graph")
        #expect(BrainTabState.nothingMatchesText == "Nothing matches these filters")
        #expect(BrainTabState.showAllVaultsTitle == "Show all vaults")
    }

    // MARK: badge

    @Test func defaultFiltersHaveNoBadge() {
        #expect(BrainTabState.badgeCount(BrainGraphModel.defaultFilters()) == 0)
    }

    @Test func badgeCountsEachSettingThatDiffersFromDefault() {
        var filters = BrainGraphModel.defaultFilters()
        filters.links[.tag] = false
        filters.links[.similar] = true
        #expect(BrainTabState.badgeCount(filters) == 2)
        filters.showOrphans = false
        filters.colourBy = .kind
        filters.vaults = [Self.v1]
        #expect(BrainTabState.badgeCount(filters) == 5)
    }

    // MARK: status line

    @Test func countsLineCountsNotesAndMemoriesAndConnections() {
        let line = BrainTabState.statusLine(
            visible: Self.visible(), truncated: false, stale: false, rateLimited: false, refreshError: nil
        )
        #expect(line.counts == "3 notes and memories · 3 connections")
        #expect(line.truncated == nil)
        #expect(line.notice == nil)
        #expect(!line.offersRetry)
    }

    @Test func oneConnectionIsSingular() {
        var filters = BrainGraphModel.defaultFilters()
        filters.links[.tag] = false
        let line = BrainTabState.statusLine(
            visible: Self.visible(Self.graph, filters), truncated: false, stale: false, rateLimited: false,
            refreshError: nil
        )
        #expect(line.counts == "3 notes and memories · 1 connection")
    }

    @Test func aFilterToggleChangesTheCounts() {
        var filters = BrainGraphModel.defaultFilters()
        filters.showOrphans = false
        let line = BrainTabState.statusLine(
            visible: Self.visible(Self.graph, filters), truncated: false, stale: false, rateLimited: false,
            refreshError: nil
        )
        #expect(line.counts == "2 notes and memories · 3 connections")
    }

    @Test func truncatedSaysMostRecent800() {
        let line = BrainTabState.statusLine(
            visible: Self.visible(), truncated: true, stale: false, rateLimited: false, refreshError: nil
        )
        #expect(line.truncated == "Most recent 800 shown")
    }

    @Test func staleSaysEarlierGraphWithRetry() {
        let line = BrainTabState.statusLine(
            visible: Self.visible(), truncated: false, stale: true, rateLimited: true, refreshError: nil
        )
        #expect(line.notice == "Showing an earlier graph")
        #expect(line.offersRetry)
        #expect(line.reason == BrainGraphErrors.rateLimitedMessage)
    }

    @Test func aRateLimitOverTheSameGraphIsOneNoticeWithRetry() {
        let line = BrainTabState.statusLine(
            visible: Self.visible(), truncated: false, stale: false, rateLimited: true, refreshError: nil
        )
        #expect(line.notice == BrainGraphErrors.rateLimitedMessage)
        #expect(line.offersRetry)
    }

    @Test func aRefreshErrorIsTheReason() {
        let line = BrainTabState.statusLine(
            visible: Self.visible(), truncated: false, stale: true, rateLimited: false, refreshError: "Network unavailable."
        )
        #expect(line.notice == "Showing an earlier graph")
        #expect(line.reason == "Network unavailable.")
    }

    // MARK: request

    @Test func everyVaultIsNoVaultParameter() {
        let req = BrainTabState.request(vaults: nil, known: [Self.v1, Self.v2], focus: nil, depth: 1, similarAsked: false)
        #expect(req == BrainGraphRequest())
    }

    @Test func namedVaultsFollowTheKnownOrder() {
        let req = BrainTabState.request(
            vaults: [Self.v2, Self.v1], known: [Self.v2, Self.v1, Self.v3], focus: nil, depth: 1, similarAsked: false
        )
        #expect(req.vaults == [Self.v2, Self.v1])
    }

    @Test func focusDepthAndSimilarPassThrough() {
        let req = BrainTabState.request(vaults: nil, known: [], focus: "A", depth: 2, similarAsked: true)
        #expect(req == BrainGraphRequest(focus: "A", depth: 2, similar: true))
    }

    @Test func anEmptyFocusIsNoFocus() {
        let req = BrainTabState.request(vaults: nil, known: [], focus: "", depth: 3, similarAsked: false)
        #expect(req == BrainGraphRequest())
    }

    @Test func similarIsAskedForOnceAndStaysAsked() {
        var filters = BrainGraphModel.defaultFilters()
        #expect(!BrainTabState.similarAsked(previously: false, filters: filters))
        filters.links[.similar] = true
        #expect(BrainTabState.similarAsked(previously: false, filters: filters))
        filters.links[.similar] = false
        #expect(BrainTabState.similarAsked(previously: true, filters: filters))
    }

    @Test func linkTogglesOtherThanSimilarNeverChangeTheRequest() {
        let base = BrainTabState.request(vaults: nil, known: [], focus: nil, depth: 1, similarAsked: false)
        var filters = BrainGraphModel.defaultFilters()
        for kind in BrainLinkKindDTO.allCases where kind != .similar { filters.links[kind] = false }
        filters.showOrphans = false
        filters.colourBy = .author
        let asked = BrainTabState.similarAsked(previously: false, filters: filters)
        let after = BrainTabState.request(vaults: filters.vaults, known: [], focus: nil, depth: 1, similarAsked: asked)
        #expect(after == base)
    }

    // MARK: vault chips

    @Test func turningOffAVaultFromAllNamesTheRest() {
        let next = BrainTabState.toggledVault(Self.v1, in: nil, known: [Self.v1, Self.v2, Self.v3])
        #expect(next == [Self.v2, Self.v3])
    }

    @Test func turningTheLastOffVaultBackOnIsEveryVault() {
        let next = BrainTabState.toggledVault(Self.v1, in: [Self.v2, Self.v3], known: [Self.v1, Self.v2, Self.v3])
        #expect(next == nil)
    }

    @Test func theLastVaultCannotBeTurnedOff() {
        #expect(!BrainTabState.canToggleVault(Self.v2, in: [Self.v2], known: [Self.v1, Self.v2]))
        #expect(BrainTabState.toggledVault(Self.v2, in: [Self.v2], known: [Self.v1, Self.v2]) == [Self.v2])
        #expect(!BrainTabState.canToggleVault(Self.v1, in: nil, known: [Self.v1]))
        #expect(BrainTabState.canToggleVault(Self.v1, in: [Self.v2], known: [Self.v1, Self.v2]))
        #expect(BrainTabState.canToggleVault(Self.v1, in: nil, known: [Self.v1, Self.v2]))
    }

    @Test func vaultIsOn() {
        #expect(BrainTabState.isVaultOn(Self.v1, in: nil))
        #expect(!BrainTabState.isVaultOn(Self.v1, in: [Self.v2]))
    }

    // MARK: focus

    @Test func authorsAreUnavailableOnlyWhenFocusedOnANonAuthor() {
        #expect(!BrainTabState.authorsUnavailable(focus: nil))
        #expect(!BrainTabState.authorsUnavailable(focus: "author:user:ABC"))
        #expect(BrainTabState.authorsUnavailable(focus: "A"))
        #expect(BrainTabState.notShownInFocusText == "Not shown in a focused graph")
    }

    @Test func aFocusedGraphSelectsItsFocusOnce() {
        let ids: Set<String> = ["A", "B"]
        #expect(BrainTabState.focusToSelect(focus: "A", selectedFor: nil, visibleIDs: ids) == "A")
        #expect(BrainTabState.focusToSelect(focus: "A", selectedFor: "A", visibleIDs: ids) == nil)
        #expect(BrainTabState.focusToSelect(focus: "Z", selectedFor: nil, visibleIDs: ids) == nil)
        #expect(BrainTabState.focusToSelect(focus: nil, selectedFor: nil, visibleIDs: ids) == nil)
        #expect(BrainTabState.focusToSelect(focus: "B", selectedFor: "A", visibleIDs: ids) == "B")
    }

    // MARK: list

    @Test func listRowsAreVisibleItemsByWeight() {
        let rows = BrainTabState.listRows(Self.visible(), vaults: [
            BrainGraphVaultDTO(id: Self.v1, name: "Personal", personal: true),
            BrainGraphVaultDTO(id: Self.v2, name: "Work", personal: false),
        ], query: "")
        #expect(rows.map(\.id) == ["B", "A", "C"])
        #expect(rows[0] == BrainListRow(id: "B", label: "Beta", kind: "Memory", vault: "Work", connections: 2))
        #expect(BrainTabState.connectionsText(rows[0].connections) == "2 connections")
        #expect(BrainTabState.connectionsText(1) == "1 connection")
        #expect(rows[2].connections == 0)
    }

    @Test func listSearchMatchesLabels() {
        let rows = BrainTabState.listRows(Self.visible(), vaults: [], query: " gam ")
        #expect(rows.map(\.id) == ["C"])
        #expect(rows[0].vault == nil)
    }

    // MARK: selection summary

    @Test func selectionSummaryNamesOneAndCountsMore() {
        let index = Self.visible().index
        #expect(BrainTabState.selectionSummary([], index: index) == "Nothing selected")
        #expect(BrainTabState.selectionSummary(["A"], index: index) == "Selected: Alpha")
        #expect(BrainTabState.selectionSummary(["A", "B"], index: index) == "2 selected")
    }
}
