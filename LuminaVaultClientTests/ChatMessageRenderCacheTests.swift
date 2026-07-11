// LuminaVaultClient/LuminaVaultClientTests/ChatMessageRenderCacheTests.swift
//
// Verifies finalized assistant turns precompute derived rendering artifacts
// once instead of re-scanning markdown in SwiftUI row bodies.

import Foundation
import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

final class ChatMessageRenderCacheTests: XCTestCase {
    func testAssistantMessageCachesImageURLs() throws {
        let message = ChatViewModel.Message(
            role: .assistant,
            content: "Here: ![chart](https://example.com/chart.png) and https://example.com/raw.webp"
        )

        XCTAssertEqual(
            message.imageURLs,
            [
                URL(string: "https://example.com/chart.png")!,
                URL(string: "https://example.com/raw.webp")!,
            ]
        )
    }

    func testAssistantMessageCachesRenderedWikilinkMarkdown() {
        let id = UUID()
        let message = ChatViewModel.Message(
            role: .assistant,
            content: "Read [[Project Plan|the plan]] and [[memory:\(id.uuidString)]]."
        )

        XCTAssertTrue(message.renderedMarkdown.contains("luminavault-wikilink://note"))
        XCTAssertTrue(message.renderedMarkdown.contains("luminavault-wikilink://memory"))
    }

    func testUserMessageDoesNotCacheAssistantOnlyArtifacts() {
        let message = ChatViewModel.Message(
            role: .user,
            content: "Look at https://example.com/raw.webp and [[Project Plan]]."
        )

        XCTAssertTrue(message.imageURLs.isEmpty)
        XCTAssertEqual(message.renderedMarkdown, message.content)
    }
}
