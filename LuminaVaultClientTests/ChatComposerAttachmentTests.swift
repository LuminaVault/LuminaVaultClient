// LuminaVaultClient/LuminaVaultClientTests/ChatComposerAttachmentTests.swift
//
// Unit tests for the composer's attachment prepend logic: the bubble
// shows a compact marker while the wire content carries the full
// extracted file (no server attachment contract — the file rides inside
// `content`).
import Testing
import Foundation
@testable import LuminaVaultClient

@MainActor
struct ChatComposerAttachmentTests {

    private func attachment(_ name: String = "Project_Alpha.pdf",
                            _ text: String = "extracted body") -> ChatViewModel.StagedAttachment {
        ChatViewModel.StagedAttachment(name: name, text: text)
    }

    // MARK: - displayText (the bubble)

    @Test func displayWithoutAttachmentIsJustTyped() {
        #expect(ChatViewModel.displayText(typed: "hello", attachment: nil) == "hello")
    }

    @Test func displayWithAttachmentPrependsMarker() {
        let result = ChatViewModel.displayText(typed: "summarize this", attachment: attachment())
        #expect(result == "📎 Project_Alpha.pdf\nsummarize this")
    }

    @Test func displayWithAttachmentOnlyIsMarker() {
        let result = ChatViewModel.displayText(typed: "", attachment: attachment())
        #expect(result == "📎 Project_Alpha.pdf")
        #expect(!result.contains("extracted body"))
    }

    // MARK: - wireText (what the model receives)

    @Test func wireWithoutAttachmentIsJustTyped() {
        #expect(ChatViewModel.wireText(typed: "hello", attachment: nil) == "hello")
    }

    @Test func wireWithAttachmentWrapsFileThenMessage() {
        let result = ChatViewModel.wireText(typed: "what changed?", attachment: attachment())
        #expect(result.contains("[Attached file: Project_Alpha.pdf]"))
        #expect(result.contains("extracted body"))
        #expect(result.hasSuffix("what changed?"))
    }

    @Test func wireWithAttachmentOnlyAddsFallbackInstruction() {
        let result = ChatViewModel.wireText(typed: "", attachment: attachment())
        #expect(result.contains("extracted body"))
        #expect(result.contains("Please use the attached file."))
    }
}
