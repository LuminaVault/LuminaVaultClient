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
        await waitUntil("assistant reply to land") { vm.messages.last?.role == .assistant }

        XCTAssertEqual(conversations.createCallCount, 1, "memory mode lazy-creates a conversation")
        XCTAssertEqual(conversations.streamReplyCallCount, 1)
        XCTAssertEqual(chat.completeCallCount, 0, "fresh client must not be called in memory mode")
        XCTAssertEqual(vm.messages.last?.role, .assistant)
        XCTAssertEqual(vm.messages.last?.content, "hi")
        XCTAssertEqual(vm.sendHapticTrigger, 1)
        XCTAssertEqual(vm.completionHapticTrigger, 1)
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
        await waitUntil("assistant reply to land") { vm.messages.last?.role == .assistant }

        XCTAssertEqual(chat.completeCallCount, 1)
        XCTAssertEqual(chat.lastRequest?.messages.last?.content, "hello")
        XCTAssertEqual(chat.lastRequest?.stream, false, "fresh transport never opens an SSE stream")
        XCTAssertEqual(conversations.createCallCount, 0, "fresh mode must not allocate a server conversation row")
        XCTAssertEqual(conversations.streamReplyCallCount, 0)
        XCTAssertEqual(vm.messages.last?.content, "hi")
    }

    func testSlashCommandRoutesToSkillsNotChatTransports() async throws {
        let conversations = SpyConversationsClient()
        let chat = SpyChatClient()
        let skills = SpySlashSkillsClient()
        let vm = ChatViewModel(
            conversationsClient: conversations,
            chatClient: chat,
            memoryClient: NoOpMemoryClient(),
            historyStore: nil,
            skillsClient: skills,
        )

        vm.composer = "/patterns sleep"
        vm.send()
        await waitUntil("slash reply to land") { vm.messages.last?.role == .assistant }

        XCTAssertEqual(skills.slashCommands, ["/patterns sleep"])
        XCTAssertEqual(conversations.createCallCount, 0)
        XCTAssertEqual(conversations.streamReplyCallCount, 0)
        XCTAssertEqual(chat.completeCallCount, 0)
        XCTAssertEqual(vm.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(vm.messages.last?.content, "## Patterns")
        XCTAssertEqual(vm.messages.last?.sourceLabel, "/pattern-detector")
        XCTAssertEqual(vm.phase, .idle)
    }

    func testWithoutSkillsClientASlashIsAnOrdinaryTurn() async throws {
        let conversations = SpyConversationsClient()
        let vm = ChatViewModel(
            conversationsClient: conversations,
            chatClient: SpyChatClient(),
            memoryClient: NoOpMemoryClient(),
            historyStore: nil,
        )
        vm.composer = "/patterns"
        vm.send()
        await waitUntil("chat reply to land") { vm.messages.last?.role == .assistant }
        XCTAssertEqual(conversations.streamReplyCallCount, 1)
        XCTAssertTrue(vm.slashSuggestions(for: "/p").isEmpty)
    }

    func testSlashFailureSurfacesAsFailedPhase() async throws {
        let skills = SpySlashSkillsClient()
        skills.failure = APIError.httpError(statusCode: 404, data: Data(#"{"error":{"message":"no skill named nope"}}"#.utf8))
        let vm = ChatViewModel(
            conversationsClient: SpyConversationsClient(),
            chatClient: SpyChatClient(),
            memoryClient: NoOpMemoryClient(),
            historyStore: nil,
            skillsClient: skills,
        )
        vm.composer = "/nope"
        vm.send()
        await waitUntil("failure") { if case .failed = vm.phase { return true }; return false }
        XCTAssertEqual(vm.messages.map(\.role), [.user])
    }

    func testSlashSuggestionsIncludeEnabledSkillsAfterLoad() async {
        let skills = SpySlashSkillsClient()
        let vm = ChatViewModel(
            conversationsClient: SpyConversationsClient(),
            chatClient: SpyChatClient(),
            memoryClient: NoOpMemoryClient(),
            historyStore: nil,
            skillsClient: skills,
        )
        XCTAssertEqual(vm.slashSuggestions(for: "/").map(\.name), ["kb-compile", "patterns", "contradict", "beliefs"])
        await vm.loadSlashCommandsIfNeeded()
        XCTAssertEqual(vm.slashSuggestions(for: "/da").map(\.name), ["daily-brief"])
        XCTAssertTrue(vm.slashSuggestions(for: "/daily-brief now").isEmpty, "a space means the argument is being typed")
    }

    func testToggleTransportFlipsState() {
        let vm = ChatViewModel(
            conversationsClient: SpyConversationsClient(),
            chatClient: SpyChatClient(),
            memoryClient: NoOpMemoryClient(),
            historyStore: nil,
        )
        // toggleTransport cycles through all three modes now that hybrid
        // (on-device + cloud) execution exists: memoryGrounded → fresh →
        // hybrid → memoryGrounded.
        XCTAssertEqual(vm.transport, .memoryGrounded)
        vm.toggleTransport()
        XCTAssertEqual(vm.transport, .fresh)
        vm.toggleTransport()
        XCTAssertEqual(vm.transport, .hybrid)
        vm.toggleTransport()
        XCTAssertEqual(vm.transport, .memoryGrounded)
    }

    func testDisabledHapticsDoNotAdvanceFeedbackTriggers() async throws {
        let vm = ChatViewModel(
            conversationsClient: SpyConversationsClient(),
            chatClient: SpyChatClient(),
            memoryClient: NoOpMemoryClient(),
            historyStore: nil,
        )
        vm.hapticsEnabled = false

        vm.composer = "quiet send"
        vm.send()
        // Wait for the turn to complete so the completion trigger had its
        // chance to fire — a negative assertion after a fixed sleep proves
        // nothing on a slow runner.
        await waitUntil("assistant reply to land") { vm.messages.last?.role == .assistant }

        XCTAssertEqual(vm.sendHapticTrigger, 0)
        XCTAssertEqual(vm.completionHapticTrigger, 0)
    }

    func testMultiModelRequestAndParallelEventsAreReduced() async throws {
        let executionID = UUID()
        let outputID = UUID()
        let conversations = SpyConversationsClient(events: [
            .parallel(.init(
                executionID: executionID,
                kind: .executionStarted,
                strategy: .debate,
                status: .running
            )),
            .parallel(.init(
                executionID: executionID,
                kind: .outputDelta,
                outputID: outputID,
                role: "Skeptic",
                route: .init(provider: .anthropic, model: "claude-sonnet-4-6"),
                stage: .answer,
                round: 1,
                delta: "A second perspective",
                status: .running
            )),
            .parallel(.init(
                executionID: executionID,
                kind: .executionCompleted,
                strategy: .debate,
                status: .completed
            )),
            .token("Synthesized"),
            .done,
        ])
        let vm = ChatViewModel(
            conversationsClient: conversations,
            chatClient: SpyChatClient(),
            memoryClient: NoOpMemoryClient(),
            historyStore: nil,
        )
        vm.multiModelEnabled = true
        vm.multiModelStrategy = .debate
        vm.composer = "Compare this"
        vm.send()
        // `.done` awaits the typewriter reveal before `finalizeAssistantTurn`
        // appends the assistant message, so the id-carrying turn can land
        // well after the parallel events are reduced.
        await waitUntil("finalized assistant turn") { vm.messages.last?.parallelExecutionID == executionID }

        XCTAssertEqual(conversations.lastRequest?.multiModel?.enabled, true)
        XCTAssertEqual(conversations.lastRequest?.multiModel?.strategy, .debate)
        XCTAssertEqual(vm.parallelExecution?.id, executionID)
        XCTAssertEqual(vm.parallelExecution?.perspectives.first?.content, "A second perspective")
        XCTAssertEqual(vm.messages.last?.parallelExecutionID, executionID)
    }
}

// MARK: - Spies

private final class SpyConversationsClient: ConversationsClientProtocol, @unchecked Sendable {
    private(set) var createCallCount = 0
    private(set) var streamReplyCallCount = 0
    private(set) var lastRequest: MessageStreamRequest?
    private let events: [QueryStreamEvent]

    init(events: [QueryStreamEvent] = [.token("hi"), .done]) {
        self.events = events
    }

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
        lastRequest = request
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
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

private final class SpySlashSkillsClient: SkillsClientProtocol, @unchecked Sendable {
    private(set) var slashCommands: [String] = []
    var failure: Error?

    func list() async throws -> SkillListResponse {
        SkillListResponse(skills: [
            SlashSkillFixture.skill("daily-brief", enabled: true),
            SlashSkillFixture.skill("weekly-memo", enabled: false),
            SlashSkillFixture.skill("pattern-detector", enabled: true),
            SlashSkillFixture.skill("hermes-research", enabled: true),
        ])
    }

    func patch(name _: String, body _: SkillPatchRequest) async throws -> LuminaVaultShared.SkillDTO {
        throw APIError.unauthorized
    }

    func runs(name _: String, limit _: Int?) async throws -> SkillRunsResponse {
        throw APIError.unauthorized
    }

    func run(name _: String, request _: SkillRunRequest) async throws -> SkillRunResponse {
        throw APIError.unauthorized
    }

    func runSlash(command: String) async throws -> SkillRunResponse {
        slashCommands.append(command)
        if let failure { throw failure }
        let now = Date()
        return SkillRunResponse(
            id: UUID(), skillName: "pattern-detector", status: .success,
            markdown: "## Patterns", startedAt: now, endedAt: now,
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
