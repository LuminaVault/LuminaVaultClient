// LuminaVaultClient/LuminaVaultClientTests/Chat/VoiceMode/ChatViewModelVoiceTests.swift
//
// HER-153 — Asserts ChatViewModel auto-speaks the assistant reply iff
// the prompt came via the mic (sendVoiceTranscript). Typed prompts
// must stay silent even when voice mode is healthy.
import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

@MainActor
final class ChatViewModelVoiceTests: XCTestCase {

    func testTypedSendDoesNotSpeak() async throws {
        let synth = StubSpeechSynthesizer()
        let voice = VoiceModeController(
            recognizer: StubSpeechRecognizer(available: true, authorized: true),
            synthesizer: synth,
        )
        let vm = ChatViewModel(
            conversationsClient: StreamingConversationsClient(reply: "hi"),
            chatClient: NoOpChatClient(),
            memoryClient: NoOpVoiceMemoryClient(),
            historyStore: nil,
            voice: voice,
        )

        vm.composer = "What's up?"
        vm.send()
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(vm.messages.last?.role, .assistant)
        XCTAssertEqual(synth.spokenTexts, [], "typed prompts must not trigger TTS")
    }

    func testVoiceSendAutoSpeaksAssistantReply() async throws {
        let synth = StubSpeechSynthesizer()
        let voice = VoiceModeController(
            recognizer: StubSpeechRecognizer(available: true, authorized: true),
            synthesizer: synth,
        )
        let vm = ChatViewModel(
            conversationsClient: StreamingConversationsClient(reply: "all good"),
            chatClient: NoOpChatClient(),
            memoryClient: NoOpVoiceMemoryClient(),
            historyStore: nil,
            voice: voice,
        )

        vm.sendVoiceTranscript("how are you")
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(vm.messages.last?.content, "all good")
        XCTAssertEqual(synth.spokenTexts, ["all good"])
    }

    func testVoiceSendFollowedByTypedSendDoesNotKeepSpeaking() async throws {
        let synth = StubSpeechSynthesizer()
        let voice = VoiceModeController(
            recognizer: StubSpeechRecognizer(available: true, authorized: true),
            synthesizer: synth,
        )
        let vm = ChatViewModel(
            conversationsClient: StreamingConversationsClient(reply: "first"),
            chatClient: NoOpChatClient(),
            memoryClient: NoOpVoiceMemoryClient(),
            historyStore: nil,
            voice: voice,
        )

        vm.sendVoiceTranscript("voice prompt")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(synth.spokenTexts, ["first"])

        vm.composer = "typed prompt"
        vm.send()
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(synth.spokenTexts, ["first"], "second reply (typed) must not be spoken")
    }
}

// MARK: - Spies / Stubs

private final class StreamingConversationsClient: ConversationsClientProtocol, @unchecked Sendable {
    let reply: String
    init(reply: String) { self.reply = reply }

    func create(_ request: ConversationCreateRequest) async throws -> ConversationDTO {
        ConversationDTO(id: UUID(), title: "", spaceId: nil, createdAt: Date(), updatedAt: Date())
    }

    func list() async throws -> ConversationListResponse {
        ConversationListResponse(conversations: [])
    }

    func get(_ id: UUID) async throws -> ConversationDetailResponse {
        ConversationDetailResponse(
            conversation: ConversationDTO(id: id, title: "", spaceId: nil, createdAt: Date(), updatedAt: Date()),
            messages: [],
        )
    }

    func delete(_ id: UUID) async throws {}

    func streamReply(
        conversationID: UUID,
        request: MessageStreamRequest,
    ) -> AsyncThrowingStream<QueryStreamEvent, any Error> {
        let reply = reply
        return AsyncThrowingStream { continuation in
            continuation.yield(.token(reply))
            continuation.yield(.done)
            continuation.finish()
        }
    }
}

private struct NoOpChatClient: ChatClientProtocol {
    func complete(_ request: ChatRequest) async throws -> ChatResponse {
        throw APIError.unauthorized
    }
}

private struct NoOpVoiceMemoryClient: MemoryClientProtocol {
    func upsert(_ request: MemoryUpsertRequest) async throws -> MemoryUpsertResponse {
        throw APIError.unauthorized
    }

    func get(id: UUID) async throws -> MemoryDTO {
        throw APIError.unauthorized
    }

    func patch(id: UUID, _ request: MemoryPatchRequest) async throws -> MemoryDTO {
        throw APIError.unauthorized
    }
}
