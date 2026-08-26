// LuminaVaultClient/LuminaVaultClientTests/StreamingMarkdownBufferTests.swift
//
// The invariant that matters for every case here: `committed + tail` is always
// exactly the text that was fed in, and `committed` never contains a block
// whose shape a later token could still change. If either breaks, the chat
// answer either loses characters or reflows when streaming stops.
import XCTest
@testable import LuminaVaultClient

final class StreamingMarkdownBufferTests: XCTestCase {
    /// Feeds `text` one character at a time, the worst case for the scanner.
    private func streamed(_ text: String) -> StreamingMarkdownBuffer {
        var buffer = StreamingMarkdownBuffer()
        for character in text {
            buffer.append(String(character))
        }
        return buffer
    }

    // MARK: - Invariants

    func testCommittedPlusTailAlwaysReconstructsTheInput() {
        let samples = [
            "plain text with no newline",
            "para one\n\npara two\n\n",
            "# heading\n\nbody\n\n```swift\nlet x = 1\n```\n\ntrailing",
            "| a | b |\n|---|---|\n| 1 | 2 |\n\nafter",
            "- one\n- two\n- three\n\n",
            "```\nunterminated fence\nstill going",
            "",
        ]
        for sample in samples {
            let buffer = streamed(sample)
            XCTAssertEqual(buffer.text, sample, "round-trip failed for \(sample.debugDescription)")
            XCTAssertEqual(buffer.committed + buffer.tail, sample)
        }
    }

    func testCharacterAtATimeMatchesOneShotAppend() {
        let text = "intro\n\n```js\nconst a = 1;\n```\n\n| x | y |\n|---|---|\n| 1 | 2 |\n\nend"
        var oneShot = StreamingMarkdownBuffer()
        oneShot.append(text)

        let incremental = streamed(text)
        XCTAssertEqual(incremental.committed, oneShot.committed)
        XCTAssertEqual(incremental.tail, oneShot.tail)
    }

    // MARK: - Paragraph boundaries

    func testBlankLineCommitsTheParagraphAboveIt() {
        let buffer = streamed("first paragraph\n\nsecond par")
        XCTAssertEqual(buffer.committed, "first paragraph\n\n")
        XCTAssertEqual(buffer.tail, "second par")
    }

    func testNothingCommitsBeforeTheFirstBoundary() {
        let buffer = streamed("still writing the very first sentence")
        XCTAssertEqual(buffer.committed, "")
        XCTAssertEqual(buffer.tail, "still writing the very first sentence")
    }

    func testSingleNewlineIsNotABoundary() {
        // A list is still growing after one newline; committing here would
        // re-lay-out the list on every item.
        let buffer = streamed("- one\n- two\n")
        XCTAssertEqual(buffer.committed, "")
        XCTAssertEqual(buffer.tail, "- one\n- two\n")
    }

    // MARK: - Fences

    func testOpenFenceHoldsBackEvenAcrossBlankLines() {
        let buffer = streamed("```swift\nlet a = 1\n\nlet b = 2\n")
        XCTAssertEqual(
            buffer.committed,
            "",
            "a blank line inside a fence is a blank line of code, not a block boundary"
        )
    }

    func testClosedFenceCommitsThroughTheClosingDelimiter() {
        let buffer = streamed("```swift\nlet a = 1\n```\nnext line")
        XCTAssertEqual(buffer.committed, "```swift\nlet a = 1\n```\n")
        XCTAssertEqual(buffer.tail, "next line")
    }

    func testTildeFencesAreRecognised() {
        let buffer = streamed("~~~\nraw\n~~~\nafter")
        XCTAssertEqual(buffer.committed, "~~~\nraw\n~~~\n")
        XCTAssertEqual(buffer.tail, "after")
    }

    func testTextBeforeAFenceCommitsOnItsBlankLine() {
        let buffer = streamed("intro\n\n```\ncode")
        XCTAssertEqual(buffer.committed, "intro\n\n")
        XCTAssertEqual(buffer.tail, "```\ncode")
    }

    // MARK: - Tables

    func testTableIsHeldBackWhileRowsAreStillArriving() {
        let buffer = streamed("| a | b |\n|---|---|\n| 1 | 2 |\n")
        XCTAssertEqual(buffer.committed, "", "committing mid-table reflows it on every new row")
    }

    func testTableCommitsOnceANonTableLineEndsTheGroup() {
        let buffer = streamed("| a | b |\n|---|---|\n| 1 | 2 |\nafter the table")
        XCTAssertEqual(buffer.committed, "| a | b |\n|---|---|\n| 1 | 2 |\n")
        XCTAssertEqual(buffer.tail, "after the table")
    }

    func testSinglePipeLineIsNotTreatedAsATable() {
        // One row is not a table; it must not commit on its own.
        let buffer = streamed("| not a table\nplain\n\n")
        XCTAssertEqual(buffer.committed, "| not a table\nplain\n\n")
        XCTAssertEqual(buffer.tail, "")
    }

    func testPipesInsideAFenceAreNotATable() {
        let buffer = streamed("```\n| a | b |\n|---|---|\n")
        XCTAssertEqual(buffer.committed, "")
    }

    // MARK: - Finalize

    func testCommitAllTakesEverythingIncludingAnUnfinishedBlock() {
        var buffer = streamed("done\n\nstill writing this")
        buffer.commitAll()
        XCTAssertEqual(buffer.committed, "done\n\nstill writing this")
        XCTAssertEqual(buffer.tail, "")
    }

    func testCommitAllClosesAnUnterminatedFence() {
        var buffer = streamed("```swift\nlet a = 1")
        buffer.commitAll()
        XCTAssertEqual(buffer.committed, "```swift\nlet a = 1")
        XCTAssertEqual(buffer.tail, "")
    }

    func testAppendAfterCommitAllKeepsAccumulating() {
        var buffer = streamed("one\n\n")
        buffer.commitAll()
        buffer.append("two\n\nthree")
        XCTAssertEqual(buffer.text, "one\n\ntwo\n\nthree")
        XCTAssertEqual(buffer.tail, "three")
    }

    // MARK: - Replace / reset

    func testReplaceDiscardsEverythingAndRescans() {
        var buffer = streamed("old content\n\nmore")
        buffer.replace(with: "brand new\n\ntail")
        XCTAssertEqual(buffer.text, "brand new\n\ntail")
        XCTAssertEqual(buffer.committed, "brand new\n\n")
        XCTAssertEqual(buffer.tail, "tail")
    }

    func testResetEmptiesTheBuffer() {
        var buffer = streamed("something\n\n")
        buffer.reset()
        XCTAssertEqual(buffer.text, "")
        XCTAssertEqual(buffer.committed, "")
        XCTAssertEqual(buffer.tail, "")
    }

    // MARK: - Multi-byte safety

    func testGraphemeClustersSurviveCharacterAtATimeStreaming() {
        let text = "emoji 👨‍👩‍👧‍👦 and accents éü\n\nnext"
        let buffer = streamed(text)
        XCTAssertEqual(buffer.text, text)
        XCTAssertEqual(buffer.committed, "emoji 👨‍👩‍👧‍👦 and accents éü\n\n")
        XCTAssertEqual(buffer.tail, "next")
    }
}
