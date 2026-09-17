// LuminaVaultClient/LuminaVaultClient/Features/Chat/ChatInboxDisplay.swift
//
// The server names a thread "New conversation" until something renames it,
// which it rarely does — so the inbox showed a column of identical rows.
// Deriving a scannable title from the first thing that was said is a display
// concern, not a wire concern, so it lives here as a pure function rather
// than in the DTO or the view body.
//
// A row has two shapes, and they are decided together so they can never
// disagree:
//
//   * The server gave the thread a name → that name, with the preview under
//     it. Two different pieces of information.
//   * It did not → the first line of the preview *is* the title, in full,
//     over two lines if it needs them, and there is no preview line. Printing
//     the same sentence twice, once cut short, told the reader nothing.

import Foundation
import LuminaVaultShared

enum ChatInboxDisplay {
    /// The server's placeholder. Matched case-insensitively and after
    /// trimming, because it has arrived with both.
    static let placeholderTitle = "New conversation"

    static let untitled = "Untitled chat"

    /// Both of a row's strings, resolved in one place. `preview` is `nil`
    /// when there is nothing left to say under the title.
    static func rowText(for item: ChatInboxItemDTO) -> (title: String, preview: String?) {
        let given = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)

        if !given.isEmpty, given.caseInsensitiveCompare(placeholderTitle) != .orderedSame {
            // A server title that is simply the first message repeats itself
            // under the row — the same sentence twice, in two sizes. Drop the
            // second copy rather than print it.
            let repeated = preview.caseInsensitiveCompare(given) == .orderedSame
            return (given, preview.isEmpty || repeated ? nil : preview)
        }

        // Derived: the whole first line, uncut. The row gives the title two
        // lines, and the rest of a multi-line preview is not worth a third.
        guard let line = firstNonEmptyLine(of: item.preview) else { return (untitled, nil) }
        return (line, nil)
    }

    /// The server `title` when it is a real one, else the first non-empty
    /// line of the preview, else `untitled`.
    static func title(for item: ChatInboxItemDTO) -> String {
        rowText(for: item).title
    }

    /// The preview line, or `nil` when the title was derived from it.
    static func preview(for item: ChatInboxItemDTO) -> String? {
        rowText(for: item).preview
    }

    private static func firstNonEmptyLine(of text: String) -> String? {
        text
            .components(separatedBy: .newlines)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}
