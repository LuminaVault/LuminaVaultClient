// The Brain screen's pure state mapping, kept out of `BrainTabView` so it can
// be tested: which card shows for which store state and filter result, the
// Filters badge, the status line, the request the controls describe, the
// vault chip rules, the focus point a focused graph selects, the list rows and
// the selection summary. No UI, no networking; `nonisolated` and `Sendable`.

import Foundation
import LuminaVaultShared

/// What fills the screen under the bar.
nonisolated enum BrainTabCard: Equatable, Sendable {
    /// The very first load, nothing on screen yet.
    case firstLoad
    case graph
    /// The graph loaded and has no notes or memories at all.
    case empty
    case failed(message: String, showAllVaults: Bool)
    /// A focused request answered 404.
    case missingFocus
    /// The graph has notes, the filters hide all of them.
    case nothingMatches
}

/// The quiet line under the bar.
nonisolated struct BrainStatusLine: Equatable, Sendable {
    /// "N notes and memories · M connections"; nil over the empty card,
    /// where there is nothing to count.
    var counts: String?
    /// "Most recent 800 shown" when the response was cut.
    var truncated: String?
    /// One notice at most: the graph shown is an earlier one, or a refresh
    /// over this very graph was refused.
    var notice: String?
    /// Why, for VoiceOver and a second line: the friendly error.
    var reason: String?
    var offersRetry: Bool
}

/// What the store says about the graph on screen, for the status line.
nonisolated struct BrainRefreshFacts: Equatable, Sendable {
    /// The response was cut at the 800-item window.
    var truncated = false
    var stale = false
    var rateLimited = false
    var refreshError: String?
    var refreshing = false
}

/// One row of `BrainListView`.
nonisolated struct BrainListRow: Equatable, Sendable, Identifiable {
    var id: String
    var label: String
    /// "Note" or "Memory".
    var kind: String
    /// The vault's name, when the graph knows it.
    var vault: String?
    var connections: Int
}

nonisolated enum BrainTabState {
    static let firstLoadText = "Mapping your notes…"
    static let emptyHeadline = "Nothing to map yet"
    static let emptySupporting = "Capture a note or a memory and it appears here, connected to the rest."
    static let captureTitle = "Capture"
    static let missingFocusText = "That is no longer in your graph. It may have been deleted."
    static let showFullGraphTitle = "Show full graph"
    static let fullGraphTitle = "Full graph"
    static let nothingMatchesText = "Nothing matches these filters"
    static let resetTitle = "Reset"
    static let retryTitle = "Retry"
    static let showAllVaultsTitle = "Show all vaults"
    static let notShownInFocusText = "Not shown in a focused graph"
    static let noSimilarText = "No similar notes found."
    static let staleText = "Showing an earlier graph"
    static let searchPrompt = "Search notes and memories"
    /// The list with nothing visible and nothing typed.
    static let listEmptyText = "No notes or memories shown"
    static let truncatedText = "Most recent \(BrainGraphRequest.unfocusedLimit) shown"

    /// The Space hub's label in `graph`. Ids in hub ids are uppercase on the wire.
    static func spaceName(_ id: UUID, in graph: BrainGraphResponse?) -> String? {
        let key = "space:\(id.uuidString)"
        return graph?.nodes.first { $0.id == key }?.label
    }

    static func isItem(_ node: BrainGraphNodeDTO) -> Bool {
        node.kind == .note || node.kind == .memory
    }

    // MARK: Card

    static func card(
        state: BrainGraphLoadState, request: BrainGraphRequest, visible: VisibleBrainGraph?
    ) -> BrainTabCard {
        switch state {
        case .loading:
            return .firstLoad
        case .missingFocus:
            return .missingFocus
        case let .failed(message):
            return .failed(message: message, showAllVaults: !(request.vaults ?? []).isEmpty)
        case let .loaded(graph):
            if !graph.nodes.contains(where: isItem) { return .empty }
            if let visible, !visible.nodes.contains(where: isItem) { return .nothingMatches }
            return .graph
        }
    }

    // MARK: Badge

    /// How many settings in the filter sheet differ from the defaults.
    static func badgeCount(_ filters: BrainGraphFilters) -> Int {
        let base = BrainGraphModel.defaultFilters()
        var count = 0
        for kind in BrainLinkKindDTO.allCases where (filters.links[kind] ?? false) != (base.links[kind] ?? false) {
            count += 1
        }
        if filters.vaults != nil { count += 1 }
        if filters.showOrphans != base.showOrphans { count += 1 }
        if filters.colourBy != base.colourBy { count += 1 }
        return count
    }

    // MARK: Status line

    static func countsText(items: Int, connections: Int) -> String {
        let things = items == 1 ? "1 note or memory" : "\(items) notes and memories"
        return "\(things) · \(connectionsText(connections))"
    }

    static func connectionsText(_ n: Int) -> String {
        n == 1 ? "1 connection" : "\(n) connections"
    }

    /// The line under the bar, or nil when there is nothing to say. The graph
    /// and nothing-matches cards count what is visible; the empty card has
    /// nothing to count but still carries a refused or failed refresh (a
    /// vault change, say) with its Retry, and the refresh spinner.
    static func statusLine(card: BrainTabCard, visible: VisibleBrainGraph?, facts: BrainRefreshFacts) -> BrainStatusLine? {
        let reason = facts.rateLimited ? BrainGraphErrors.rateLimitedMessage : facts.refreshError
        let notice = facts.stale ? staleText : reason
        var line = BrainStatusLine(
            counts: nil, truncated: nil, notice: notice, reason: facts.stale ? reason : nil, offersRetry: notice != nil
        )
        switch card {
        case .graph, .nothingMatches:
            guard let visible else { return nil }
            line.counts = countsText(items: visible.nodes.count(where: isItem), connections: visible.edges.count)
            line.truncated = facts.truncated ? truncatedText : nil
            return line
        case .empty:
            return notice != nil || facts.refreshing ? line : nil
        case .firstLoad, .failed, .missingFocus:
            return nil
        }
    }

    /// Changes with every response that lands (and with the known vaults,
    /// which name the vault colours); nil while none is on screen.
    static func derivationKey(loadSerial: Int?, knownVaults: [UUID]) -> String {
        guard let loadSerial else { return "none" }
        return "\(loadSerial)|" + knownVaults.map(\.uuidString).joined(separator: ",")
    }

    // MARK: Request

    /// The request the controls describe. Vaults follow the order of the
    /// known vaults (unknown ids last, by id) so the same set is the same query.
    static func request(
        vaults: Set<UUID>?, known: [UUID], focus: String?, depth: Int, similarAsked: Bool
    ) -> BrainGraphRequest {
        var named: [UUID]?
        if let vaults, !vaults.isEmpty {
            let inOrder = known.filter { vaults.contains($0) }
            let rest = vaults.subtracting(inOrder).sorted { $0.uuidString < $1.uuidString }
            named = inOrder + rest
        }
        let focus = (focus?.isEmpty ?? true) ? nil : focus
        return BrainGraphRequest(vaults: named, focus: focus, depth: focus == nil ? 1 : depth, similar: similarAsked)
    }

    /// Similar is fetched the first time it is turned on and kept from then
    /// on: turning it off again filters in place and asks nothing.
    static func similarAsked(previously: Bool, filters: BrainGraphFilters) -> Bool {
        previously || (filters.links[.similar] ?? false)
    }

    // MARK: Vault chips

    static func isVaultOn(_ id: UUID, in vaults: Set<UUID>?) -> Bool {
        vaults?.contains(id) ?? true
    }

    /// Any chip that is off can be turned on; the last one on cannot go off.
    static func canToggleVault(_ id: UUID, in vaults: Set<UUID>?, known: [UUID]) -> Bool {
        guard isVaultOn(id, in: vaults) else { return true }
        return (vaults?.count ?? known.count) > 1
    }

    /// The vault set after tapping a chip. Every vault on is `nil`.
    static func toggledVault(_ id: UUID, in vaults: Set<UUID>?, known: [UUID]) -> Set<UUID>? {
        guard canToggleVault(id, in: vaults, known: known) else { return vaults }
        var next = vaults ?? Set(known)
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        return next.isSuperset(of: known) ? nil : next
    }

    // MARK: Focus

    /// A focus that is not an author hub omits authors from the request, so
    /// the Authors toggle and colour-by-author have nothing to show.
    static func authorsUnavailable(focus: String?) -> Bool {
        guard let focus, !focus.isEmpty else { return false }
        return !BrainGraphRequest.isAuthorFocus(focus)
    }

    /// The focus point to select now: once per focus, when it is on screen.
    static func focusToSelect(focus: String?, selectedFor: String?, visibleIDs: Set<String>) -> String? {
        guard let focus, !focus.isEmpty, focus != selectedFor, visibleIDs.contains(focus) else { return nil }
        return focus
    }

    // MARK: List

    /// Visible notes and memories, heaviest first (then by label), whose label
    /// contains `query`.
    static func listRows(_ visible: VisibleBrainGraph, vaults: [BrainGraphVaultDTO], query: String) -> [BrainListRow] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let names = Dictionary(vaults.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return visible.nodes
            .filter { isItem($0) && (q.isEmpty || $0.label.localizedStandardContains(q)) }
            .sorted {
                if $0.weight != $1.weight { return $0.weight > $1.weight }
                let order = $0.label.localizedStandardCompare($1.label)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
            .map { node in
                BrainListRow(
                    id: node.id,
                    label: node.label,
                    kind: BrainGraphCopy.nodeKindName(node.kind),
                    vault: node.vaultID.flatMap { names[$0] },
                    connections: visible.index.edgesOf[node.id]?.count ?? 0
                )
            }
    }

    // MARK: 2D / Constellation

    static let viewMenuTitle = "View"
    static let twoDTitle = "2D"
    static let constellationTitle = "Constellation"

    static func viewTitle(_ view: BrainViewChoice) -> String {
        switch view {
        case .twoD: twoDTitle
        case .threeD: constellationTitle
        }
    }

    /// What VoiceOver hears once a switch has happened (web `SWITCH_NOTES`).
    static func switchNote(_ view: BrainViewChoice) -> String {
        switch view {
        case .threeD: "Showing the 3D constellation"
        case .twoD: "Showing the 2D graph"
        }
    }

    /// Picking `next` while `shown` is on screen: the prefs to store and the
    /// note to announce, or nil when it is already shown (nothing is created,
    /// stored or said). A switch never asks for a graph and keeps the
    /// selection: both live outside the renderer.
    static func switchView(
        shown: BrainViewChoice, to next: BrainViewChoice, filters: BrainGraphFilters
    ) -> (prefs: BrainPrefs, note: String)? {
        guard next != shown else { return nil }
        return (BrainPrefs(filters: filters, view: next), switchNote(next))
    }

    /// The selection tray's height before it has been measured once: one row
    /// of chips and one of actions.
    static let trayHeightEstimate: CGFloat = 120

    /// Whether a sheet covers the graph, so nothing on it should move.
    static func isCovered(filters: Bool, list: Bool, capture: Bool, detail: Bool, reasoning: Bool) -> Bool {
        filters || list || capture || detail || reasoning
    }

    // MARK: Selection

    /// The canvas's accessibility value.
    static func selectionSummary(_ selected: [String], index: BrainGraphIndex) -> String {
        switch selected.count {
        case 0: "Nothing selected"
        case 1: "Selected: \(index.byID[selected[0]]?.label ?? selected[0])"
        default: "\(selected.count) selected"
        }
    }
}
