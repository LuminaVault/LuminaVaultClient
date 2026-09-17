// LuminaVaultClient/LuminaVaultClient/Features/Chat/ChatInboxDisplay.swift
//
// The server names a thread "New conversation" until something renames it,
// which it rarely does — so the inbox showed a column of identical rows.
// Deriving a scannable title from the first thing that was said is a display
// concern, not a wire concern, so it lives here as a pure function rather
// than in the DTO or the view body.

import Foundation
import LuminaVaultShared

enum ChatInboxDisplay {
    /// The server's placeholder. Matched case-insensitively and after
    /// trimming, because it has arrived with both.
    static let placeholderTitle = "New conversation"

    /// A row title is one line; past this it stops being scannable and
    /// starts competing with the preview underneath it.
    static let derivedTitleLimit = 60

    static let untitled = "Untitled chat"

    /// The server `title` when it is a real one, else the first non-empty
    /// line of the preview, else `untitled`.
    static func title(for item: ChatInboxItemDTO) -> String {
        let given = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !given.isEmpty, given.caseInsensitiveCompare(placeholderTitle) != .orderedSame {
            return given
        }
        guard let line = firstNonEmptyLine(of: item.preview) else { return untitled }
        guard line.count > derivedTitleLimit else { return line }
        return String(line.prefix(derivedTitleLimit)) + "…"
    }

    /// The preview line, unless the title was derived from it whole — the
    /// same sentence printed twice in one row tells the reader nothing the
    /// first line did not.
    static func preview(for item: ChatInboxItemDTO) -> String? {
        let preview = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preview.isEmpty, preview != title(for: item) else { return nil }
        return preview
    }

    private static func firstNonEmptyLine(of text: String) -> String? {
        text
            .components(separatedBy: .newlines)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}
