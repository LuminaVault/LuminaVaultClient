// LuminaVaultClient/LuminaVaultClient/Features/Shell/CommandPaletteMatcher.swift
//
// How typing narrows the command palette. Ported from the web client's
// `src/lib/command/commands.ts` so both palettes rank the same way.
//
// Matching is a subsequence match, not a substring one: "ins" finds
// "Insights" and "stg" finds "Settings". That is what people expect from a
// palette, and it means a lot matches — so ranking is what makes it usable.
// An exact name beats a prefix, a prefix beats a word boundary, and a
// scattered hit comes last. Ties break alphabetically so the list cannot
// reshuffle between keystrokes and strand the arrow keys.

import Foundation

nonisolated enum CommandPaletteMatcher {
    struct Entry: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
        let group: String
        /// Extra words that should match but are not worth showing.
        var keywords: [String] = []
    }

    /// True when every character of `query` appears in `text`, in order.
    /// Case-insensitive; spaces in the query are ignored.
    static func subsequenceMatch(_ text: String, _ query: String) -> Bool {
        let needle = query.lowercased().filter { !$0.isWhitespace }
        guard !needle.isEmpty else { return true }
        var haystack = text.lowercased()[...]
        for character in needle {
            guard let found = haystack.firstIndex(of: character) else { return false }
            haystack = haystack[haystack.index(after: found)...]
        }
        return true
    }

    /// Lower is better.
    static func score(_ entry: Entry, _ query: String) -> Int {
        let label = entry.label.lowercased()
        let needle = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return 0 }
        if label == needle { return 0 }
        if label.hasPrefix(needle) { return 1 }
        if label.contains(" " + needle) { return 2 }
        if label.contains(needle) { return 3 }
        return 4
    }

    static func filter(_ entries: [Entry], _ query: String) -> [Entry] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return entries
            .filter { subsequenceMatch(([$0.label, $0.group] + $0.keywords).joined(separator: " "), needle) }
            .sorted { lhs, rhs in
                let left = score(lhs, needle)
                let right = score(rhs, needle)
                if left != right { return left < right }
                return lhs.label.localizedCompare(rhs.label) == .orderedAscending
            }
    }
}
