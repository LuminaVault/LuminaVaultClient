// LuminaVaultClient/LuminaVaultClientTests/ChatViewModelFailureTelemetryTests.swift
//
// When a send fails, the chat surface used to record the failure only as
// SwiftUI view state (`phase = .failed`). Nothing reached Sentry, PostHog or
// the unified log, and the banner showed the server's message with no hint
// of which layer produced it. These tests pin the telemetry event and the
// status-prefixed banner for a raw Hummingbird 400.

import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

@MainActor
final class ChatViewModelFailureTelemetryTests: XCTestCase {
    private static let hummingbird400 = Data(
        #"{"error":{"message":"Coding key `pinnedMemoryIDs` not found."}}"#.utf8
    )

    private func makeViewModel(
        conversations: any ConversationsClientProtocol,
        telemetry: SpyTelemetry
    ) -> ChatViewModel {
        let vm = ChatViewModel(
            conversationsClient: conversations,
            chatClient: FailingChatClient(),
            memoryClient: FailingMemoryClient(),
            historyStore: nil,
            telemetry: telemetry
        )
        vm.transport = .memoryGrounded
        return vm
    }

    func testRawServer400ShowsStatusPrefixedMessage() async throws {
        let telemetry = SpyTelemetry()
        let vm = makeViewModel(
            conversations: FailingConversationsClient(
                error: APIError.httpError(statusCode: 400, data: Self.hummingbird400)
            ),
            telemetry: telemetry
        )

        vm.composer = "What patterns do I have in my Stocks space lately?"
        vm.send()
        await waitUntil("send to fail") { if case .failed = vm.phase { return true } else { return false } }

        XCTAssertEqual(
            vm.phase,
            .failed(message: "Server rejected the request (400): Coding key `pinnedMemoryIDs` not found.")
        )
    }

    func testFailedSendTracksAnEventWithStatusTransportAndMultiModel() async throws {
        let telemetry = SpyTelemetry()
        let vm = makeViewModel(
            conversations: FailingConversationsClient(
                error: APIError.httpError(statusCode: 400, data: Self.hummingbird400)
            ),
            telemetry: telemetry
        )
        vm.multiModelEnabled = true

        vm.composer = "hello"
        vm.send()
        await waitUntil("send to fail") { if case .failed = vm.phase { return true } else { return false } }

        XCTAssertEqual(telemetry.events.count, 1)
        let event = try XCTUnwrap(telemetry.events.first)
        XCTAssertEqual(event.name, "chat_send_failed")
        XCTAssertEqual(event.properties["status"], "400")
        XCTAssertEqual(event.properties["transport"], "memory_grounded")
        XCTAssertEqual(event.properties["multi_model"], "true")
        XCTAssertEqual(event.properties["error_kind"], "http_error")
        XCTAssertEqual(event.properties["server_message"], "Coding key `pinnedMemoryIDs` not found.")
        XCTAssertNil(event.properties["content"], "never ship what the user typed")
    }

    func testCodedServerErrorKeepsItsOwnWording() async throws {
        let telemetry = SpyTelemetry()
        let byok = Data(
            #"{"error":{"code":"byok_keys_required","message":"Add an API key to keep chatting."}}"#.utf8
        )
        let vm = makeViewModel(
            conversations: FailingConversationsClient(error: APIError.httpError(statusCode: 403, data: byok)),
            telemetry: telemetry
        )

        vm.composer = "hello"
        vm.send()
        await waitUntil("send to fail") { if case .failed = vm.phase { return true } else { return false } }

        XCTAssertEqual(vm.phase, .failed(message: "Add an API key to keep chatting."))
        XCTAssertEqual(vm.recoveryActions, [.addKey, .switchToManaged])
    }
}

// MARK: - Doubles

private final class SpyTelemetry: TelemetryProtocol, @unchecked Sendable {
    struct Event: Equatable {
        let name: String
        let properties: [String: String]
    }

    private(set) var events: [Event] = []

    func track(_ event: String, properties: [String: String]) {
        events.append(Event(name: event, properties: properties))
    }
}

private final class FailingConversationsClient: ConversationsClientProtocol, @unchecked Sendable {
    let error: any Error
    init(error: any Error) { self.error = error }

    func create(_ request: ConversationCreateRequest) async throws -> ConversationDTO { throw error }
    func list() async throws -> ConversationListResponse { ConversationListResponse(conversations: []) }
    func get(_ id: UUID) async throws -> ConversationDetailResponse { throw error }
    func delete(_ id: UUID) async throws {}
    func streamReply(
        conversationID: UUID,
        request: MessageStreamRequest
    ) -> AsyncThrowingStream<QueryStreamEvent, any Error> {
        AsyncThrowingStream { $0.finish(throwing: error) }
    }
}

private struct FailingChatClient: ChatClientProtocol {
    func complete(_ request: ChatRequest) async throws -> ChatResponse { throw APIError.unauthorized }
}

private struct FailingMemoryClient: MemoryClientProtocol {
    func upsert(_ request: MemoryUpsertRequest) async throws -> MemoryUpsertResponse { throw APIError.unauthorized }
    func get(id: UUID) async throws -> MemoryDTO { throw APIError.unauthorized }
    func patch(id: UUID, _ request: MemoryPatchRequest) async throws -> MemoryDTO { throw APIError.unauthorized }
    func list(limit: Int, offset: Int) async throws -> MemoryListResponse { throw APIError.unauthorized }
    func search(_ request: MemorySearchRequest) async throws -> MemorySearchResponse { throw APIError.unauthorized }
    func delete(id: UUID) async throws { throw APIError.unauthorized }
}
