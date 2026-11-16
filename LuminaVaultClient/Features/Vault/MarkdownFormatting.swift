// LuminaVaultClient/LuminaVaultClient/Features/Vault/MarkdownFormatting.swift
// Backlog E5.4: the edits behind the note editor's keyboard toolbar. Pure:
// text plus a selection (character offsets) in, text plus a selection out.
// Each action toggles: applying it to text that already has it removes it.
import Foundation

enum MarkdownFormatting {
    enum Action: String, CaseIterable, Identifiable {
        case bold, italic, code, heading, bullet, task, quote, link

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .bold: "Bold"
            case .italic: "Italic"
            case .code: "Code"
            case .heading: "Heading"
            case .bullet: "Bulleted list"
            case .task: "Checklist"
            case .quote: "Quote"
            case .link: "Link to a note"
            }
        }

        var systemImage: String {
            switch self {
            case .bold: "bold"
            case .italic: "italic"
            case .code: "chevron.left.forwardslash.chevron.right"
            case .heading: "number"
            case .bullet: "list.bullet"
            case .task: "checklist"
            case .quote: "text.quote"
            case .link: "link"
            }
        }
    }

    /// A selection as character offsets; `lower == upper` is a cursor.
    struct Selection: Equatable {
        var lower: Int
        var upper: Int

        static func cursor(_ at: Int) -> Selection {
            Selection(lower: at, upper: at)
        }
    }

    static func apply(_ action: Action, to text: String, selection: Selection) -> (String, Selection) {
        let sel = clamp(selection, in: text)
        switch action {
        case .bold: return wrap(text, sel, "**", "**")
        case .italic: return wrap(text, sel, "*", "*")
        case .code: return wrap(text, sel, "`", "`")
        case .link: return wrap(text, sel, "[[", "]]")
        case .heading: return heading(text, sel)
        case .bullet: return prefixLines(text, sel, "- ")
        case .task: return prefixLines(text, sel, "- [ ] ")
        case .quote: return prefixLines(text, sel, "> ")
        }
    }

    // MARK: - Inline

    /// Wraps the selection, or removes the markers when they already surround
    /// it. With a cursor, inserts both markers and leaves the cursor between.
    private static func wrap(_ text: String, _ sel: Selection, _ open: String, _ close: String) -> (String, Selection) {
        var chars = Array(text)
        let o = Array(open), c = Array(close)
        let before = sel.lower - o.count
        let after = sel.upper
        if before >= 0, after + c.count <= chars.count,
           Array(chars[before ..< sel.lower]) == o, Array(chars[after ..< after + c.count]) == c,
           !(open == "*" && isBoldMarker(chars, before: before, after: after))
        {
            chars.removeSubrange(after ..< after + c.count)
            chars.removeSubrange(before ..< sel.lower)
            return (String(chars), Selection(lower: before, upper: sel.upper - o.count))
        }
        chars.insert(contentsOf: c, at: sel.upper)
        chars.insert(contentsOf: o, at: sel.lower)
        return (String(chars), Selection(lower: sel.lower + o.count, upper: sel.upper + o.count))
    }

    /// `**x**` with the cursor on `x`: those `*`s belong to bold, so italic
    /// adds its own instead of stripping half of bold's. One or three `*`s on
    /// each side do hold an italic marker.
    private static func isBoldMarker(_ chars: [Character], before: Int, after: Int) -> Bool {
        // `before` is the marker's index, so the run ends at `before`.
        var left = 0
        while before - left >= 0, chars[before - left] == "*" {
            left += 1
        }
        var right = 0
        while after + right < chars.count, chars[after + right] == "*" {
            right += 1
        }
        return left == 2 && right == 2
    }

    // MARK: - Lines

    /// Offsets of the first character of each line the selection touches.
    private static func lineStarts(_ chars: [Character], _ sel: Selection) -> [Int] {
        var start = sel.lower
        while start > 0, chars[start - 1] != "\n" {
            start -= 1
        }
        var starts = [start]
        var i = start
        while i < sel.upper, i < chars.count {
            if chars[i] == "\n", i + 1 <= sel.upper {
                starts.append(i + 1)
            }
            i += 1
        }
        // A selection that ends right after a newline doesn't take the next line.
        if starts.count > 1, starts.last == sel.upper, sel.upper > sel.lower {
            starts.removeLast()
        }
        return starts
    }

    private static func hasPrefix(_ chars: [Character], at i: Int, _ p: [Character]) -> Bool {
        i + p.count <= chars.count && Array(chars[i ..< i + p.count]) == p
    }

    /// Adds `prefix` to every touched line, or removes it when every line has it.
    private static func prefixLines(_ text: String, _ sel: Selection, _ prefix: String) -> (String, Selection) {
        var chars = Array(text)
        let p = Array(prefix)
        let starts = lineStarts(chars, sel)
        let remove = starts.allSatisfy { hasPrefix(chars, at: $0, p) }
        var lower = sel.lower, upper = sel.upper
        for start in starts.reversed() {
            if remove {
                chars.removeSubrange(start ..< start + p.count)
                upper -= p.count
                if start < lower {
                    lower = max(start, lower - p.count)
                }
            } else {
                chars.insert(contentsOf: p, at: start)
                upper += p.count
                if start <= lower {
                    lower += p.count
                }
            }
        }
        return (String(chars), Selection(lower: lower, upper: max(lower, upper)))
    }

    /// Cycles the current line: text → `## ` → `### ` → text. Other heading
    /// levels become `## `.
    private static func heading(_ text: String, _ sel: Selection) -> (String, Selection) {
        var chars = Array(text)
        guard let start = lineStarts(chars, .cursor(sel.lower)).first else { return (text, sel) }
        var hashes = 0
        while start + hashes < chars.count, chars[start + hashes] == "#" {
            hashes += 1
        }
        let hasSpace = start + hashes < chars.count && chars[start + hashes] == " "
        let existing = hashes > 0 && hashes <= 6 && hasSpace ? hashes + 1 : 0
        let next = switch (existing > 0, hashes) {
        case (true, 2): "### "
        case (true, 3): ""
        default: "## "
        }
        chars.replaceSubrange(start ..< start + existing, with: Array(next))
        let delta = next.count - existing
        let shift = { (offset: Int) in offset >= start + existing ? offset + delta : start + next.count }
        return (String(chars), Selection(lower: shift(sel.lower), upper: shift(sel.upper)))
    }

    private static func clamp(_ sel: Selection, in text: String) -> Selection {
        let n = text.count
        let lower = min(max(0, min(sel.lower, sel.upper)), n)
        let upper = min(max(0, max(sel.lower, sel.upper)), n)
        return Selection(lower: lower, upper: upper)
    }
}
