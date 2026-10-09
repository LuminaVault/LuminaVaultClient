//
//  AgentRunActivityCopy.swift
//  LuminaVaultWidgets
//

import Foundation

enum AgentRunActivityCopy {
    /// The status line, with the stale case said honestly: once the app has
    /// been suspended for a while the follower is not listening, so the last
    /// known step is no longer news.
    static func status(_ state: AgentRunAttributes.ContentState, isStale: Bool) -> String {
        if isStale, state.stage == .working || state.stage == .waiting {
            return "may have finished — tap to check"
        }
        return state.status
    }

    static func glyph(_ state: AgentRunAttributes.ContentState) -> String {
        switch state.stage {
        case .waiting: "hand.raised.fill"
        case .done: "checkmark"
        case .failed: "exclamationmark"
        case .working: toolGlyph(state.toolLabel)
        }
    }

    /// An SF Symbol for the running tool's verb phrase (`MuseToolLabel`).
    static func toolGlyph(_ label: String?) -> String {
        guard let label = label?.lowercased() else { return "ellipsis" }
        let table: [(String, String)] = [
            ("web", "globe"),
            ("page", "doc.text"),
            ("vault", "books.vertical"),
            ("file", "doc"),
            ("code", "terminal"),
            ("calendar", "calendar"),
            ("email", "envelope"),
            ("weather", "cloud.sun"),
            ("location", "location"),
            ("health", "heart"),
            ("image", "photo"),
            ("memory", "brain"),
            ("schedul", "clock"),
            ("search", "magnifyingglass"),
        ]
        return table.first { label.contains($0.0) }?.1 ?? "sparkles"
    }
}
