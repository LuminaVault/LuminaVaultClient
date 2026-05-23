// LuminaVaultClient/LuminaVaultClientTests/ChatViewModelTransportTests.swift
//
// HER-107 — asserts the transport toggle in ChatViewModel routes each
// send to the correct client. Uses lightweight in-process spies (no
// URLSession). Streaming behavior of `executeStream` is covered by
// `BaseHTTPClientSSETests`.
import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

@MainActor
final class ChatViewModelTransportTests: XCTestCase {

    func testMemoryGroundedRoutesToConversationsStream() async throws {
        let conversations = SpyConversationsClient()
        let chat = SpyChatClient()
        let vm = ChatViewModel(
            conversationsClient: conversations,
            chatClient: chat,
            memoryClient: NoOpMemoryClient(),
            historyStore: nil,
        )
        XCTAssertEqual(vm.transport, .memoryGrounded)

        vm.composer = "hello"
        vm.send()
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(conversations.createCallCount, 1, "memory mode lazy-creates a conversation")
        XCTAssertEqual(conversations.streamReplyCallCount, 1)
        XCTAssertEqual(chat.completeCallCount, 0, "fresh client must not be called in memory mode")
        XCTAssertEqual(vm.messages.last?.role, .assistant)
        XCTAssertEqual(vm.messages.last?.content, "hi")
    }

    func testFreshRoutesToChatCompletionsNotConversations() async throws {
        let conversations = SpyConversationsClient()
        let chat = SpyChatClient()
        let vm = ChatViewModel(
            conversationsClient: conversations,
            chatClient: chat,
            memoryClient: NoOpMemoryClient(),
            historyStore: nil,
        )
        vm.transport = .fresh

        vm.composer = "hello"
        vm.send()
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(chat.completeCallCount, 1)
        XCTAssertEqual(chat.lastRequest?.messages.last?.content, "hello")
        XCTAssertEqual(chat.lastRequest?.stream, false, "fresh transport never opens an SSE stream")
        XCTAssertEqual(conversations.createCallCount, 0, "fresh mode must not allocate a server conversation row")
        XCTAssertEqual(conversations.streamReplyCallCount, 0)
        XCTAssertEqual(vm.messages.last?.content, "hi")
    }

    func testToggleTransportFlipsState() {
        let vm = ChatViewModel(
            conversationsClient: SpyConversationsClient(),
            chatClient: SpyChatClient(),
            memoryClient: NoOpMemoryClient(),
            historyStore: nil,
        )
        XCTAssertEqual(vm.transport, .memoryGrounded)
        vm.toggleTransport()
        XCTAssertEqual(vm.transport, .fresh)
        vm.toggleTransport()
        XCTAssertEqual(vm.transport, .memoryGrounded)
    }
}

// MARK: - Spies

private final class SpyConversationsClient: ConversationsClientProtocol, @unchecked Sendable {
    private(set) var createCallCount = 0
    private(set) var streamReplyCallCount = 0

    func create(_ request: ConversationCreateRequest) async throws -> ConversationDTO {
        createCallCount += 1
        return ConversationDTO(
            id: UUID(),
            title: "test",
            spaceId: nil,
            createdAt: Date(),
            updatedAt: Date(),
        )
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
        streamReplyCallCount += 1
        return AsyncThrowingStream { continuation in
            continuation.yield(.token("hi"))
            continuation.yield(.done)
            continuation.finish()
        }
    }
}

private final class SpyChatClient: ChatClientProtocol, @unchecked Sendable {
    private(set) var completeCallCount = 0
    private(set) var lastRequest: ChatRequest?

    func complete(_ request: ChatRequest) async throws -> ChatResponse {
        completeCallCount += 1
        lastRequest = request
        let message = ChatMessage(role: "assistant", content: "hi")
        return ChatResponse(
            id: "stub",
            model: "stub-model",
            message: message,
            raw: HermesUpstreamResponse(
                id: "stub",
                model: "stub-model",
                choices: [HermesUpstreamChoice(index: 0, message: message, finishReason: "stop")],
            ),
        )
    }
}

private struct NoOpMemoryClient: MemoryClientProtocol {
    func upsert(_ request: MemoryUpsertRequest) async throws -> MemoryUpsertResponse {
        throw APIError.unauthorized
    }

    func get(id: UUID) async throws -> MemoryDTO {
        throw APIError.unauthorized
    }
}
