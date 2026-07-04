// LuminaVaultClient/LuminaVaultClient/Features/Settings/Soul/SoulCoreParser.swift
//
// Template v2 — splits a SOUL.md document around the server-managed locked
// core covenant (`<!-- lv:core:vN:start -->` … `<!-- lv:core:vN:end -->`).
// UI-only presentation logic: the editor and the onboarding confirm screen
// show the core as a read-only card and bind text editing to the editable
// remainder. The server is the enforcement point — it strips and re-injects
// the canonical core on every write regardless of what the client sends —
// so this parser only needs to be tolerant, never authoritative.

import Foundation

struct SoulDocumentParts: Equatable, Sendable {
    /// Front-matter + heading preceding the core block ("" when none).
    let prefix: String
    /// The full marker-to-marker core block, nil when the document has none
    /// (e.g. a pre-v2 SOUL.md that the server hasn't migrated yet).
    let core: String?
    /// Everything after the core — the part the user may edit.
    let editable: String
}

enum SoulCoreParser {
    /// Matches any core version so a future server-side `v2` bump keeps
    /// rendering read-only without a client update.
    private static let corePattern =
        "<!--\\s*lv:core:v\\d+:start\\s*-->[\\s\\S]*?<!--\\s*lv:core:v\\d+:end\\s*-->"

    static func parse(_ markdown: String) -> SoulDocumentParts {
        guard let regex = try? NSRegularExpression(pattern: corePattern),
              let match = regex.firstMatch(
                  in: markdown,
                  range: NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
              ),
              let range = Range(match.range, in: markdown)
        else {
            return SoulDocumentParts(prefix: "", core: nil, editable: markdown)
        }
        let prefix = String(markdown[..<range.lowerBound])
        let core = String(markdown[range])
        var editable = String(markdown[range.upperBound...])
        if let firstContent = editable.firstIndex(where: { !$0.isWhitespace }) {
            editable = String(editable[firstContent...])
        } else {
            editable = ""
        }
        return SoulDocumentParts(prefix: prefix, core: core, editable: editable)
    }

    /// Reassembles the document for PUT. Framing mirrors the server's
    /// injector (single blank line around the core) so a round trip through
    /// the server is byte-stable.
    static func assemble(_ parts: SoulDocumentParts, editable: String) -> String {
        guard let core = parts.core else { return editable }
        let prefix = parts.prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = ""
        if !prefix.isEmpty { out += prefix + "\n\n" }
        out += core
        let trimmedEditable = editable.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEditable.isEmpty { out += "\n\n" + trimmedEditable }
        return out
    }
}
