// LuminaVaultClient/LuminaVaultClient/Features/Vault/WikilinkCompletion.swift
// Backlog E5.3: `[[` suggestions in the note editor. Pure helpers, the same
// rules as the web editor (LuminaVaultWebApp src/lib/vault/wikilink-complete.ts):
// typing `[[` lists notes; `#` after a note's name lists its headings;
// accepting writes `[[Note]]` or `[[Note#Heading]]`.
import Foundation

enum WikilinkCompletion {
    /// The unfinished `[[…` the cursor is in.
    struct Context: Equatable {
        /// Where the typed query starts (just after `[[`).
        let start: String.Index
        let query: String
        /// Set once `#` is typed.
        let note: String?
        let heading: String?
    }

    struct NoteOption: Equatable {
        /// What the link says: the note name, or its path when names clash.
        let label: String
        /// The folder, shown beside the name.
        let detail: String
        let path: String
    }

    private static let maxQuery = 120

    /// The open wikilink ending at `cursor`, or nil. Stops at a newline, `]]`,
    /// `|` (an alias is free text) and a stray `[`.
    static func context(in text: String, cursor: String.Index) -> Context? {
        let lineStart = text[..<cursor].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let before = text[lineStart ..< cursor]
        guard let open = before.range(of: "[[", options: .backwards) else { return nil }
        let query = String(before[open.upperBound...])
        if query.contains("]]") || query.contains("|") || query.contains("[") || query.count > maxQuery {
            return nil
        }
        guard let hash = query.firstIndex(of: "#") else {
            return Context(start: open.upperBound, query: query, note: nil, heading: nil)
        }
        return Context(
            start: open.upperBound,
            query: query,
            note: String(query[..<hash]),
            heading: String(query[query.index(after: hash)...])
        )
    }

    /// `notes/Weekly sync.md` → `Weekly sync`.
    static func noteName(_ path: String) -> String {
        let last = path.split(separator: "/").last.map(String.init) ?? path
        return stripMarkdownExtension(last)
    }

    static func isMarkdown(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasSuffix(".md") || lower.hasSuffix(".markdown")
    }

    private static func stripMarkdownExtension(_ path: String) -> String {
        let lower = path.lowercased()
        if lower.hasSuffix(".markdown") {
            return String(path.dropLast(9))
        }
        if lower.hasSuffix(".md") {
            return String(path.dropLast(3))
        }
        return path
    }

    /// Markdown files ranked for `query`: names that start with it, names that
    /// contain it, then paths that contain it. Clashing names link by path.
    static func rankNotes(_ paths: [String], query: String, limit: Int = 8) -> [NoteOption] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var seen = Set<String>()
        let notes = paths.filter { isMarkdown($0) && seen.insert($0).inserted }
        var nameCount: [String: Int] = [:]
        for path in notes {
            nameCount[noteName(path).lowercased(), default: 0] += 1
        }
        func score(_ path: String) -> Int? {
            if q.isEmpty {
                return 0
            }
            let name = noteName(path).lowercased()
            if name.hasPrefix(q) {
                return 0
            }
            if name.contains(q) {
                return 1
            }
            if path.lowercased().contains(q) {
                return 2
            }
            return nil
        }
        var scored: [(path: String, score: Int)] = []
        for path in notes {
            if let s = score(path) {
                scored.append((path, s))
            }
        }
        scored.sort { a, b in
            if a.score != b.score {
                return a.score < b.score
            }
            return noteName(a.path).localizedStandardCompare(noteName(b.path)) == .orderedAscending
        }
        var options: [NoteOption] = []
        for entry in scored.prefix(limit) {
            let name = noteName(entry.path)
            let unique = nameCount[name.lowercased()] == 1
            var folder = ""
            if let slash = entry.path.range(of: "/", options: .backwards) {
                folder = String(entry.path[..<slash.lowerBound])
            }
            let label = unique ? name : stripMarkdownExtension(entry.path)
            options.append(NoteOption(label: label, detail: folder, path: entry.path))
        }
        return options
    }

    /// ATX headings outside fenced code, in order, without trailing `#`s.
    static func headings(of markdown: String) -> [String] {
        var out: [String] = []
        var fence: Character?
        for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = Substring(raw)
            let indent = line.prefix { $0 == " " }.count
            let body = line.dropFirst(min(indent, 3))
            if indent <= 3, let first = body.first, first == "`" || first == "~",
               body.prefix(while: { $0 == first }).count >= 3
            {
                if fence == nil {
                    fence = first
                } else if fence == first {
                    fence = nil
                }
                continue
            }
            if fence != nil || indent > 3 {
                continue
            }
            let hashes = body.prefix { $0 == "#" }.count
            guard (1 ... 6).contains(hashes) else { continue }
            let rest = body.dropFirst(hashes)
            guard let space = rest.first, space == " " || space == "\t" else { continue }
            var title = rest.trimmingCharacters(in: .whitespaces)
            while title.hasSuffix("#") {
                title.removeLast()
            }
            title = title.trimmingCharacters(in: .whitespaces)
            if !title.isEmpty {
                out.append(title)
            }
        }
        return out
    }

    /// Headings that start with, then contain, `prefix`; first occurrence only.
    static func rankHeadings(_ headings: [String], prefix: String, limit: Int = 8) -> [String] {
        var seen = Set<String>()
        let unique = headings.filter { seen.insert($0).inserted }
        let q = prefix.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            return Array(unique.prefix(limit))
        }
        let starts = unique.filter { $0.lowercased().hasPrefix(q) }
        let contains = unique.filter { !$0.lowercased().hasPrefix(q) && $0.lowercased().contains(q) }
        return Array((starts + contains).prefix(limit))
    }

    /// Replaces the query with `target` and closes the link unless the text
    /// after the cursor already does. Returns the new text and the cursor
    /// offset (in characters) just after `]]`.
    static func apply(target: String, to text: String, context: Context, cursor: String.Index) -> (String, Int) {
        let closes = text[cursor...].hasPrefix("]]")
        let insert = closes ? target : target + "]]"
        var out = text
        out.replaceSubrange(context.start ..< cursor, with: insert)
        let offset = text.distance(from: text.startIndex, to: context.start) + target.count + 2
        return (out, offset)
    }
}
