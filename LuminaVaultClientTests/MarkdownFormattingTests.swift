// LuminaVaultClient/LuminaVaultClientTests/MarkdownFormattingTests.swift
// Backlog E5.4 — the note editor's keyboard toolbar edits.

import XCTest
@testable import LuminaVaultClient

final class MarkdownFormattingTests: XCTestCase {
    private typealias F = MarkdownFormatting
    private typealias Sel = MarkdownFormatting.Selection

    /// `|` marks the cursor, `{` `}` a selection, in both input and expected.
    private func run(_ action: F.Action, _ marked: String) -> String {
        let (text, sel) = parse(marked)
        let (out, outSel) = F.apply(action, to: text, selection: sel)
        return render(out, outSel)
    }

    private func parse(_ marked: String) -> (String, Sel) {
        var text = ""
        var lower = 0, upper = 0
        for ch in marked {
            switch ch {
            case "|": lower = text.count; upper = text.count
            case "{": lower = text.count
            case "}": upper = text.count
            default: text.append(ch)
            }
        }
        return (text, Sel(lower: lower, upper: upper))
    }

    private func render(_ text: String, _ sel: Sel) -> String {
        var chars = Array(text)
        if sel.lower == sel.upper {
            chars.insert("|", at: sel.lower)
        } else {
            chars.insert("}", at: sel.upper)
            chars.insert("{", at: sel.lower)
        }
        return String(chars)
    }

    func testBoldWrapsTogglesAndInsertsAtCursor() {
        XCTAssertEqual(run(.bold, "a {word} b"), "a **{word}** b")
        XCTAssertEqual(run(.bold, "a **{word}** b"), "a {word} b")
        XCTAssertEqual(run(.bold, "a | b"), "a **|** b")
    }

    func testItalicDoesNotStripHalfOfBold() {
        XCTAssertEqual(run(.italic, "**{x}**"), "***{x}***")
        XCTAssertEqual(run(.italic, "*{x}*"), "{x}")
        XCTAssertEqual(run(.italic, "***{x}***"), "**{x}**")
    }

    func testCodeAndLink() {
        XCTAssertEqual(run(.code, "{let x}"), "`{let x}`")
        XCTAssertEqual(run(.link, "see |"), "see [[|]]")
        XCTAssertEqual(run(.link, "see {Plan}"), "see [[{Plan}]]")
    }

    func testBulletAddsAndRemovesOnEveryLine() {
        XCTAssertEqual(run(.bullet, "one|"), "- one|")
        XCTAssertEqual(run(.bullet, "{one\ntwo}"), "- {one\n- two}")
        XCTAssertEqual(run(.bullet, "- {one\n- two}"), "{one\ntwo}")
        // Mixed lines: add to all rather than remove from some.
        XCTAssertEqual(run(.bullet, "{- one\ntwo}"), "- {- one\n- two}")
    }

    func testTaskAndQuoteOnlyTouchTheCursorLine() {
        XCTAssertEqual(run(.task, "a\nb|\nc"), "a\n- [ ] b|\nc")
        XCTAssertEqual(run(.quote, "a\n> b|\nc"), "a\nb|\nc")
    }

    func testSelectionEndingAtNewlineSkipsNextLine() {
        XCTAssertEqual(run(.quote, "{a\n}b"), "> {a\n}b")
    }

    func testHeadingCycles() {
        XCTAssertEqual(run(.heading, "Title|"), "## Title|")
        XCTAssertEqual(run(.heading, "## Title|"), "### Title|")
        XCTAssertEqual(run(.heading, "### Title|"), "Title|")
        XCTAssertEqual(run(.heading, "# Title|"), "## Title|")
        XCTAssertEqual(run(.heading, "#tag|"), "## #tag|")
        XCTAssertEqual(run(.heading, "x\n|"), "x\n## |")
    }

    func testOutOfRangeSelectionIsClamped() {
        let (out, sel) = F.apply(.bold, to: "ab", selection: Sel(lower: 5, upper: 9))
        XCTAssertEqual(out, "ab****")
        XCTAssertEqual(sel, .cursor(4))
    }
}
