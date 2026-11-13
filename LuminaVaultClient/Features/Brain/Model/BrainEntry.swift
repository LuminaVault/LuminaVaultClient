// The Brain tab's ways in, as small values the tab's owner holds and the tab
// reads: an entry request ("Show in graph", the `brain` deep link), and the
// active vault as the tab last saw it.

import Foundation

/// A request to open the Brain tab on a focus, or on the full graph when
/// `focus` is nil. `token` makes each request distinct (the same memory shown
/// twice is two requests) and lets the tab tell one it has applied from a new
/// one, so returning to the tab never re-applies an old request.
nonisolated struct BrainEntryRequest: Equatable, Sendable {
    var focus: String?
    var token: Int

    /// What the tab does with a request: the focus (nil = full graph) at the
    /// screen's default depth.
    struct Applied: Equatable, Sendable {
        var focus: String?
        var depth: Int
        var token: Int

        /// An entry that names a focus looks at every vault: a memory in a
        /// vault the filter excluded must be found, not reported deleted.
        /// An entry without one leaves the filter as it is.
        func vaults(keeping current: Set<UUID>?) -> Set<UUID>? {
            focus == nil ? current : nil
        }

        /// Whether applying this over what the screen shows changes the graph
        /// request. When it does not, nothing will load, so the tab must
        /// select the focus point itself; when it does, the load does.
        /// Compares the requests the tab sends (`BrainTabState.request`, as
        /// the store does), not the raw filter values: an empty vault set and
        /// nil ask for the same graph.
        func changesRequest(
            focus current: String?, depth currentDepth: Int, vaults currentVaults: Set<UUID>?,
            known: [UUID], similarAsked: Bool
        ) -> Bool {
            let now = BrainTabState.request(
                vaults: currentVaults, known: known, focus: current, depth: currentDepth, similarAsked: similarAsked
            )
            let next = BrainTabState.request(
                vaults: vaults(keeping: currentVaults), known: known, focus: focus, depth: depth,
                similarAsked: similarAsked
            )
            return now.query != next.query
        }
    }

    static let defaultDepth = 1

    /// The next request after the one with `token` (the shell keeps a counter
    /// that only grows, so a recreated tab can never mistake a new request
    /// for one it has applied).
    static func next(focus: String?, afterToken token: Int) -> BrainEntryRequest {
        BrainEntryRequest(focus: focus.map(normalized), token: token + 1)
    }

    /// "Show in graph" for a memory: its node id is its uppercased UUID.
    static func memory(_ id: UUID, afterToken token: Int) -> BrainEntryRequest {
        next(focus: id.uuidString, afterToken: token)
    }

    /// What the shell keeps once the tab has applied `applied`: nothing, unless
    /// a newer request has arrived since.
    static func acknowledge(_ current: BrainEntryRequest?, applied: Int?) -> BrainEntryRequest? {
        guard let current, current.token != applied else { return nil }
        return current
    }

    /// Ids on the wire carry every uuid in uppercase (`SPACE:<UUID>` hubs and
    /// the like); anything else in an id is left as it is.
    static func normalized(_ id: String) -> String {
        id.split(separator: ":", omittingEmptySubsequences: false)
            .map { part in UUID(uuidString: String(part)).map(\.uuidString) ?? String(part) }
            .joined(separator: ":")
    }

    /// What to apply for `entry`, or nil when there is none or its token is
    /// the one already applied. A new request replaces any focus already set.
    static func apply(_ entry: BrainEntryRequest?, lastApplied: Int?) -> Applied? {
        guard let entry, entry.token != lastApplied else { return nil }
        return Applied(focus: entry.focus.map(normalized), depth: defaultDepth, token: entry.token)
    }
}

/// The active vault as the Brain tab last read it. The graph covers every
/// vault, so a change never asks for a graph; it only says that an answer
/// scoped to the old vault no longer applies.
nonisolated struct BrainActiveVaultTracker: Sendable {
    private(set) var current: UUID?
    private var read = false

    /// Records a read; true when it differs from an earlier one.
    mutating func observe(_ id: UUID?) -> Bool {
        defer { current = id; read = true }
        return read && current != id
    }
}
