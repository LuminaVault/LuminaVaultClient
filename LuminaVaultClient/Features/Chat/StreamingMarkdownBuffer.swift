// LuminaVaultClient/LuminaVaultClient/Features/Chat/StreamingMarkdownBuffer.swift
//
// Splits a partially-streamed assistant answer into a *committed* prefix that
// is safe to hand to MarkdownUI and an *uncommitted* tail that is not.
//
// The problem this solves: re-parsing the whole answer through MarkdownUI on
// every typewriter tick is both expensive and visually wrong. A half-arrived
// fence renders as a paragraph until its closing ``` lands; a half-arrived
// table renders as pipe-separated text until the row group completes — so the
// answer visibly reflows the instant streaming stops.
//
// A prefix is committable when it ends on a block boundary that later tokens
// cannot retroactively change:
//
//   * a blank line outside a fence — the paragraph/list/quote above it is
//     closed,
//   * the newline after a fence's closing delimiter,
//   * the end of a table row group, once a non-table line proves no more rows
//     are coming.
//
// Everything after the last boundary renders as plain `Text` with the caret,
// and is promoted a block at a time as boundaries arrive.
//
// Cost is O(characters appended). Each character is examined once on its way
// into `tail`, and `tail` never holds more than one unfinished block, so the
// prefix moves that flush it are bounded by block size rather than by answer
// length.
import Foundation

struct StreamingMarkdownBuffer: Equatable {
    /// Longest prefix of the answer ending on a completed block boundary.
    /// Safe to render as markdown — it will not change shape later.
    private(set) var committed = ""

    /// The block still being written. Renders as plain text behind the caret.
    private(set) var tail = ""

    /// Characters of `tail` that are now committable, resolved but not yet
    /// flushed. Flushing happens at the end of each `append`.
    private var committableCount = 0

    /// Offset in `tail` where the line currently being read begins.
    private var lineStart = 0

    /// The line currently being read, without its terminator.
    private var line = ""

    /// Fence delimiter we are currently inside (``` or ~~~, possibly longer).
    private var openFence: String?

    /// Offset in `tail` where the current table row group began.
    private var tableStart: Int?

    /// The whole answer seen so far.
    var text: String {
        committed + tail
    }

    // MARK: - Mutation

    /// Reset to empty. Used when the turn is cleared.
    mutating func reset() {
        self = StreamingMarkdownBuffer()
    }

    /// Replace the whole answer. Rescans from scratch, which is correct
    /// because nothing about the previous text survives — this is the
    /// `.summary` path, where the server's final text supersedes the tokens.
    mutating func replace(with newText: String) {
        reset()
        append(newText)
    }

    /// Extend the answer and advance the boundary scan over just the new part.
    mutating func append(_ delta: String) {
        guard !delta.isEmpty else { return }
        for character in delta {
            tail.append(character)
            if character == "\n" {
                consumeLine()
                line = ""
                lineStart = tail.count
            } else {
                line.append(character)
            }
        }
        closeTableGroupIfCurrentLineCannotBeARow()
        flush()
    }

    /// Commit everything, boundary or not. Called once the turn is finalized:
    /// the text cannot change again, so the whole answer is safe to render.
    mutating func commitAll() {
        committed = text
        tail = ""
        committableCount = 0
        lineStart = 0
        line = ""
        openFence = nil
        tableStart = nil
    }

    // MARK: - Line classification

    /// Called with `line` holding the just-completed line and `tail` already
    /// including its newline.
    private mutating func consumeLine() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Fences win over everything else: a blank line inside a code block is
        // just a blank line of code, and a `|` inside one is not a table.
        if let fence = openFence {
            if trimmed.hasPrefix(fence) {
                openFence = nil
                committableCount = tail.count
            }
            return
        }
        if let fence = Self.fenceDelimiter(of: trimmed) {
            closeTableGroup(endingAt: lineStart)
            openFence = fence
            return
        }

        if Self.isTableRow(trimmed) {
            if tableStart == nil {
                tableStart = lineStart
            }
            return
        }
        closeTableGroup(endingAt: lineStart)

        if trimmed.isEmpty {
            committableCount = tail.count
        }
    }

    /// A table row has to start with `|`, so the first non-blank character of
    /// the following line already settles whether the group is over — no need
    /// to wait for that line's newline, which may never arrive if the answer
    /// ends there.
    private mutating func closeTableGroupIfCurrentLineCannotBeARow() {
        guard tableStart != nil, openFence == nil else { return }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("|") else { return }
        closeTableGroup(endingAt: lineStart)
    }

    /// Commit a completed table, but only once a following line proves no more
    /// rows are coming. Committing mid-table would re-lay-out the whole table
    /// on every new row — the exact churn this type exists to avoid.
    private mutating func closeTableGroup(endingAt end: Int) {
        guard let start = tableStart else { return }
        tableStart = nil
        // A header row plus a delimiter row is the minimum real table.
        let group = tail.dropFirst(start).prefix(end - start)
        guard group.split(separator: "\n").count >= 2 else { return }
        committableCount = max(committableCount, end)
    }

    /// Move the resolved prefix out of `tail` and rebase the offsets onto what
    /// is left. `tail` is one unfinished block, so this is cheap.
    private mutating func flush() {
        guard committableCount > 0 else { return }
        let cut = tail.index(tail.startIndex, offsetBy: committableCount)
        committed += tail[..<cut]
        tail.removeSubrange(..<cut)
        lineStart = max(0, lineStart - committableCount)
        tableStart = tableStart.map { max(0, $0 - committableCount) }
        committableCount = 0
    }

    /// Returns the delimiter if the line opens or closes a fence.
    private static func fenceDelimiter(of trimmed: String) -> String? {
        for marker in ["```", "~~~"] where trimmed.hasPrefix(marker) {
            let run = trimmed.prefix { $0 == marker.first }
            return run.count >= 3 ? String(run) : nil
        }
        return nil
    }

    /// A GFM table row or delimiter row. Deliberately loose — the cost of a
    /// false positive is one extra block held back for one more line.
    private static func isTableRow(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("|") && trimmed.count > 1
    }
}
