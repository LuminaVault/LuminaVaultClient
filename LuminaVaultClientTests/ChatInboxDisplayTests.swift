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

    func testTruncatesALongPreviewLineToSixtyCharactersWithAnEllipsis() {
        let long = String(repeating: "a", count: 80)
        let title = ChatInboxDisplay.title(for: item(title: "", preview: long))
        XCTAssertEqual(title, String(repeating: "a", count: 60) + "…")
    }

    func testAPreviewLineAtExactlySixtyCharactersIsNotTruncated() {
        let exact = String(repeating: "b", count: 60)
        let title = ChatInboxDisplay.title(for: item(title: "", preview: exact))
        XCTAssertEqual(title, exact)
    }

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
