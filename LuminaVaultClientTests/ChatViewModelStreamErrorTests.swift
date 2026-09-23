// LuminaVaultClient/LuminaVaultClientTests/ChatViewModelStreamErrorTests.swift
//
// A refusal that arrives mid-stream used to be a bare message: the HTTP path
// offered "Add API key" / "Use managed brain" / "Upgrade" from the envelope's
// `cta`, but once the stream had started the same refusal came as
// `.error(String)` and the buttons were lost. Since LuminaVaultShared 5.20.0 it
// can arrive as `.errorDetail`, carrying the same tokens.

import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

@MainActor
final class ChatViewModelStreamErrorTests: XCTestCase {
    private func send(ending event: QueryStreamEvent) async -> ChatViewModel {
        let vm = ChatViewModel(
            conversationsClient: ErrorStreamConversationsClient(final: event),
            chatClient: NoOpStreamErrorChatClient(),
            memoryClient: NoOpStreamErrorMemoryClient(),
            historyStore: nil
        )
        vm.composer = "hello"
        vm.send()
        await waitUntil("stream to fail") { if case .failed = vm.phase { return true } else { return false } }
        return vm
    }

    func testDetailedStreamErrorOffersItsRecoveryActions() async {
        let vm = await send(ending: .errorDetail(StreamErrorDTO(
            message: "You've used today's free messages.",
            code: "free_lane_exhausted",
            cta: ["add_key", "switch_to_managed", "not_a_token"]
        )))

        XCTAssertEqual(vm.phase, .failed(message: "You've used today's free messages."))
        XCTAssertEqual(vm.recoveryActions, [.addKey, .switchToManaged])
    }

    func testPlainStreamErrorOffersNothing() async {
        let vm = await send(ending: .error("upstream failure"))

        XCTAssertEqual(vm.phase, .failed(message: "upstream failure"))
        XCTAssertEqual(vm.recoveryActions, [])
    }
}

// MARK: - Stubs

private final class ErrorStreamConversationsClient: ConversationsClientProtocol, @unchecked Sendable {
    let final: QueryStreamEvent
    init(final: QueryStreamEvent) { self.final = final }

    func create(_ request: ConversationCreateRequest) async throws -> ConversationDTO {
        ConversationDTO(id: UUID(), title: "", spaceId: nil, createdAt: Date(), updatedAt: Date())
    }

    func list() async throws -> ConversationListResponse {
        ConversationListResponse(conversations: [])
    }

    func get(_ id: UUID) async throws -> ConversationDetailResponse {
        ConversationDetailResponse(
            conversation: ConversationDTO(id: id, title: "", spaceId: nil, createdAt: Date(), updatedAt: Date()),
            messages: []
        )
    }

    func delete(_ id: UUID) async throws {}

    func streamReply(
        conversationID: UUID,
        request: MessageStreamRequest
    ) -> AsyncThrowingStream<QueryStreamEvent, any Error> {
        let final = final
        return AsyncThrowingStream { continuation in
            continuation.yield(final)
            continuation.finish()
        }
    }
}

private struct NoOpStreamErrorChatClient: ChatClientProtocol {
    func complete(_ request: ChatRequest) async throws -> ChatResponse {
        throw APIError.unauthorized
    }
}

private struct NoOpStreamErrorMemoryClient: MemoryClientProtocol {
    func upsert(_ request: MemoryUpsertRequest) async throws -> MemoryUpsertResponse {
        throw APIError.unauthorized
    }

    func get(id: UUID) async throws -> MemoryDTO {
        throw APIError.unauthorized
    }

    func patch(id: UUID, _ request: MemoryPatchRequest) async throws -> MemoryDTO {
        throw APIError.unauthorized
    }

    func list(limit: Int, offset: Int) async throws -> MemoryListResponse {
        throw APIError.unauthorized
    }

    func search(_ request: MemorySearchRequest) async throws -> MemorySearchResponse {
        throw APIError.unauthorized
    }

    func delete(id: UUID) async throws {
        throw APIError.unauthorized
    }
}
