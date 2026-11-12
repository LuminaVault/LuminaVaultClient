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
    }

    static let defaultDepth = 1

    /// "Show in graph" for a memory: its node id is its uppercased UUID.
    static func memory(_ id: UUID, after previous: BrainEntryRequest?) -> BrainEntryRequest {
        BrainEntryRequest(focus: normalized(id.uuidString), token: (previous?.token ?? 0) + 1)
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
