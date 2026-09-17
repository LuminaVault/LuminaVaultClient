// LuminaVaultClient/LuminaVaultClientTests/ChatInboxDisplayTests.swift
//
// The inbox used to render a wall of rows all called "New conversation" —
// that is the server's placeholder, not a title, and it made the list
// useless. `ChatInboxDisplay` is the pure rule that turns a row into
// something a human can scan, so it is tested without a view.

import Foundation
import LuminaVaultShared
import XCTest

@testable import LuminaVaultClient

@MainActor
final class ChatInboxDisplayTests: XCTestCase {
    private func item(title: String, preview: String) -> ChatInboxItemDTO {
        ChatInboxItemDTO(
            id: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!,
            title: title,
            preview: preview,
            messageCount: 1,
            lastMessageAt: Date(timeIntervalSince1970: 1_757_865_429)
        )
    }

    func testKeepsAServerTitle() {
        let title = ChatInboxDisplay.title(for: item(title: "Quarterly plan", preview: "anything"))
        XCTAssertEqual(title, "Quarterly plan")
    }

    func testPlaceholderTitleFallsBackToThePreview() {
        let title = ChatInboxDisplay.title(
            for: item(title: "New conversation", preview: "How do I seal a secret for horus?")
        )
        XCTAssertEqual(title, "How do I seal a secret for horus?")
    }

    /// The server's placeholder has arrived with stray case and whitespace
    /// before; matching it exactly would let those rows through.
    func testPlaceholderMatchIgnoresCaseAndWhitespace() {
        let title = ChatInboxDisplay.title(
            for: item(title: "  new conversation ", preview: "Where did the lease go?")
        )
        XCTAssertEqual(title, "Where did the lease go?")
    }

    func testEmptyTitleFallsBackToThePreview() {
        let title = ChatInboxDisplay.title(for: item(title: "", preview: "Draft the demand-hour note"))
        XCTAssertEqual(title, "Draft the demand-hour note")
    }

    func testUsesTheFirstNonEmptyPreviewLine() {
        let title = ChatInboxDisplay.title(
            for: item(title: "New conversation", preview: "\n   \nSummarise yesterday\nand today")
        )
        XCTAssertEqual(title, "Summarise yesterday")
    }

    func testEmptyTitleAndEmptyPreviewFallsBackToUntitled() {
        XCTAssertEqual(ChatInboxDisplay.title(for: item(title: "", preview: "")), "Untitled chat")
        XCTAssertEqual(
            ChatInboxDisplay.title(for: item(title: "New conversation", preview: "  \n \n ")),
            "Untitled chat"
        )
    }

    /// A derived title is never cut: the row gives it two lines instead, and
    /// a 60-character "…" only meant the same sentence appeared twice, once
    /// truncated and once whole.
    func testADerivedTitleIsTheFullFirstLine() {
        let long = "How long does the whisper service take on a two-minute voice note, end to end?"
        XCTAssertTrue(long.count > 60)
        let row = ChatInboxDisplay.rowText(for: item(title: "New conversation", preview: long))
        XCTAssertEqual(row.title, long)
        XCTAssertNil(row.preview)
    }

    // MARK: - Preview

    func testADerivedTitleLeavesNoPreviewLine() {
        XCTAssertNil(
            ChatInboxDisplay.preview(for: item(title: "New conversation", preview: "Draft the note"))
        )
        XCTAssertNil(
            ChatInboxDisplay.preview(for: item(title: "", preview: String(repeating: "c", count: 80)))
        )
    }

    func testARealTitleKeepsItsPreview() {
        let row = ChatInboxDisplay.rowText(
            for: item(title: "Sealing secrets", preview: "Bound to the namespace")
        )
        XCTAssertEqual(row.title, "Sealing secrets")
        XCTAssertEqual(row.preview, "Bound to the namespace")
    }

    /// The remainder of a multi-line preview is shown nowhere: the first line
    /// became the title, and a third line of text in a list row is clutter.
    func testAMultiLinePreviewContributesOnlyItsFirstLine() {
        let row = ChatInboxDisplay.rowText(
            for: item(title: "New conversation", preview: "Summarise yesterday\nand today\nand tomorrow")
        )
        XCTAssertEqual(row.title, "Summarise yesterday")
        XCTAssertNil(row.preview)
    }

    /// A thread named after its own opening line: the preview would print the
    /// same sentence a second time, one size smaller.
    func testARealTitleEqualToItsPreviewDropsThePreview() {
        let row = ChatInboxDisplay.rowText(
            for: item(title: "Sealing secrets", preview: "  sealing secrets\n")
        )
        XCTAssertEqual(row.title, "Sealing secrets")
        XCTAssertNil(row.preview)
    }

    func testEmptyPreviewIsNil() {
        XCTAssertNil(ChatInboxDisplay.preview(for: item(title: "Sealing secrets", preview: " \n ")))
    }

    // MARK: - Message count

    /// The row's count used to read "1 messages". The fix is automatic
    /// grammar agreement, which the localization engine resolves at render
    /// time — so this asserts the resolved string, not the view. Note that
    /// `String(localized:)` hands back the raw markup here; only the
    /// attributed resolution actually inflects.
    func testMessageCountInflects() {
        let one = AttributedString(localized: "^[\(1) message](inflect: true)")
        let four = AttributedString(localized: "^[\(4) message](inflect: true)")
        XCTAssertEqual(String(one.characters), "1 message")
        XCTAssertEqual(String(four.characters), "4 messages")
    }
}
