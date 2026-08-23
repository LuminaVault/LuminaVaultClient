// LuminaVaultClient/LuminaVaultClientTests/ChatViewModelLoadConversationTests.swift
//
// Opening a thread from the Chats inbox used to rebuild every turn as
// `Message(sources: [])` with no `parallelExecutionID` and no `modelLabel`,
// so citation chips, the model badge and the multi-model comparison link all
// vanished the moment a conversation was reopened. These cover the three
// recovery paths that replaced it:
//
//   * `parallelExecutionID` read straight off the wire DTO,
//   * `sources` / `modelLabel` merged back from the local snapshot,
//   * `sources` hydrated from the memory store for turns the snapshot
//     could not cover,
//
// plus the offline fallback, where a failed fetch falls back to the cached
// snapshot instead of erroring over an empty transcript.
import LuminaVaultShared
import os
import XCTest

@testable import LuminaVaultClient

@MainActor
final class ChatViewModelLoadConversationTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatLoadConversationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    private func makeViewModel(
        conversations: any ConversationsClientProtocol,
        memory: any MemoryClientProtocol = FailingMemoryClient(),
        store: ChatHistoryStore?
    ) -> ChatViewModel {
        ChatViewModel(
            conversationsClient: conversations,
            chatClient: FailingChatClient(),
            memoryClient: memory,
            historyStore: store
        )
    }

    private func wireMessage(
        id: UUID = UUID(),
        conversationID: UUID,
        role: ConversationMessageRole,
        content: String,
        sourceMemoryIDs: [UUID] = [],
        parallelExecutionID: UUID? = nil
    ) -> ConversationMessageDTO {
        ConversationMessageDTO(
            id: id,
            conversationId: conversationID,
            role: role,
            content: content,
            sourceMemoryIDs: sourceMemoryIDs,
            parallelExecutionID: parallelExecutionID,
            createdAt: Date()
        )
    }

    // MARK: - Wire fields

    func testCarriesParallelExecutionIDFromTheWire() async {
        let conversationID = UUID()
        let executionID = UUID()
        let client = StubConversationsClient(detail: .init(
            conversation: .stubbed(id: conversationID),
            messages: [
                wireMessage(conversationID: conversationID, role: .user, content: "compare these"),
                wireMessage(
                    conversationID: conversationID,
                    role: .assistant,
                    content: "here you go",
                    parallelExecutionID: executionID
                ),
            ]
        ))
        let vm = makeViewModel(conversations: client, store: nil)

        await vm.loadConversation(id: conversationID)

        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertEqual(
            vm.messages.last?.parallelExecutionID,
            executionID,
            "the comparison link must survive reopening the thread"
        )
    }

    // MARK: - Local snapshot merge

    func testRecoversModelLabelAndSourcesFromTheLocalSnapshot() async throws {
        let conversationID = UUID()
        let assistantID = UUID()
        let store = ChatHistoryStore(baseURL: tempDir)

        let cachedHit = QueryHitDTO(id: UUID(), content: "a cited memory", distance: 0.1)
        let cached = ChatViewModel.Message(
            id: assistantID,
            role: .assistant,
            content: "here you go",
            sources: [cachedHit],
            modelLabel: "claude-opus-5"
        )
        try await store.save(.init(
            id: conversationID,
            transport: .memoryGrounded,
            messages: [cached],
            updatedAt: Date(),
            lastReadMessageID: assistantID
        ))

        let client = StubConversationsClient(detail: .init(
            conversation: .stubbed(id: conversationID),
            messages: [
                wireMessage(
                    id: assistantID,
                    conversationID: conversationID,
                    role: .assistant,
                    content: "here you go"
                ),
            ]
        ))
        let vm = makeViewModel(conversations: client, store: store)

        await vm.loadConversation(id: conversationID)

        XCTAssertEqual(vm.messages.first?.modelLabel, "claude-opus-5")
        XCTAssertEqual(vm.messages.first?.sources.map(\.content), ["a cited memory"])
        XCTAssertEqual(vm.lastReadMessageID, assistantID, "scroll position restores with the thread")
    }

    // MARK: - Memory hydration

    func testHydratesSourceChipsFromTheMemoryStoreWhenTheCacheCannot() async {
        let conversationID = UUID()
        let memoryID = UUID()
        let memory = StubMemoryClient(memories: [
            memoryID: .stubbed(id: memoryID, content: "grounded in this note"),
        ])
        let client = StubConversationsClient(detail: .init(
            conversation: .stubbed(id: conversationID),
            messages: [
                wireMessage(
                    conversationID: conversationID,
                    role: .assistant,
                    content: "answer",
                    sourceMemoryIDs: [memoryID]
                ),
            ]
        ))
        let vm = makeViewModel(conversations: client, memory: memory, store: nil)

        await vm.loadConversation(id: conversationID)

        XCTAssertEqual(vm.messages.first?.sources.map(\.content), ["grounded in this note"])
        XCTAssertEqual(memory.getCallCount, 1)
    }

    /// The same memory cited by many turns must be read once, not once per turn.
    func testDeduplicatesMemoryReadsAcrossTurns() async {
        let conversationID = UUID()
        let memoryID = UUID()
        let memory = StubMemoryClient(memories: [
            memoryID: .stubbed(id: memoryID, content: "shared source"),
        ])
        let client = StubConversationsClient(detail: .init(
            conversation: .stubbed(id: conversationID),
            messages: (0 ..< 5).map { index in
                wireMessage(
                    conversationID: conversationID,
                    role: .assistant,
                    content: "answer \(index)",
                    sourceMemoryIDs: [memoryID]
                )
            }
        ))
        let vm = makeViewModel(conversations: client, memory: memory, store: nil)

        await vm.loadConversation(id: conversationID)

        XCTAssertEqual(memory.getCallCount, 1, "five turns citing one memory is one read")
        XCTAssertEqual(vm.messages.filter { !$0.sources.isEmpty }.count, 5)
    }

    func testDoesNotTouchTheMemoryStoreWhenNoTurnCitesAnything() async {
        let conversationID = UUID()
        let memory = StubMemoryClient(memories: [:])
        let client = StubConversationsClient(detail: .init(
            conversation: .stubbed(id: conversationID),
            messages: [wireMessage(conversationID: conversationID, role: .user, content: "hi")]
        ))
        let vm = makeViewModel(conversations: client, memory: memory, store: nil)

        await vm.loadConversation(id: conversationID)

        XCTAssertEqual(memory.getCallCount, 0)
    }

    // MARK: - Offline fallback

    func testFallsBackToTheCachedSnapshotWhenTheFetchFails() async throws {
        let conversationID = UUID()
        let store = ChatHistoryStore(baseURL: tempDir)
        try await store.save(.init(
            id: conversationID,
            transport: .memoryGrounded,
            messages: [
                .init(role: .user, content: "cached question"),
                .init(role: .assistant, content: "cached answer"),
            ],
            updatedAt: Date()
        ))

        let client = StubConversationsClient(error: APIError.unauthorized)
        let vm = makeViewModel(conversations: client, store: store)

        await vm.loadConversation(id: conversationID)

        XCTAssertEqual(vm.messages.map(\.content), ["cached question", "cached answer"])
        XCTAssertEqual(vm.phase, .idle, "an offline open shows the cache, not an error")
    }

    func testSurfacesTheErrorWhenThereIsNoCachedSnapshot() async {
        let client = StubConversationsClient(error: APIError.unauthorized)
        let vm = makeViewModel(conversations: client, store: ChatHistoryStore(baseURL: tempDir))

        await vm.loadConversation(id: UUID())

        XCTAssertTrue(vm.messages.isEmpty)
        guard case .failed = vm.phase else {
            return XCTFail("expected a failed phase, got \(vm.phase)")
        }
    }
}

// MARK: - Stubs

private extension ConversationDTO {
    static func stubbed(id: UUID) -> ConversationDTO {
        ConversationDTO(id: id, title: "thread", spaceId: nil, createdAt: Date(), updatedAt: Date())
    }
}

private extension MemoryDTO {
    static func stubbed(id: UUID, content: String) -> MemoryDTO {
        MemoryDTO(
            id: id,
            content: content,
            tags: [],
            createdAt: Date(),
            lat: nil,
            lng: nil,
            accuracyM: nil,
            placeName: nil,
            reviewState: "auto",
            provenance: nil,
            createdByUserId: nil
        )
    }
}

private final class StubConversationsClient: ConversationsClientProtocol, @unchecked Sendable {
    private let result: Result<ConversationDetailResponse, any Error>

    init(detail: ConversationDetailResponse) {
        result = .success(detail)
    }

    init(error: any Error) {
        result = .failure(error)
    }

    func create(_: ConversationCreateRequest) async throws -> ConversationDTO {
        throw APIError.unauthorized
    }

    func list() async throws -> ConversationListResponse {
        ConversationListResponse(conversations: [])
    }

    func get(_: UUID) async throws -> ConversationDetailResponse {
        try result.get()
    }

    func delete(_: UUID) async throws {}

    func streamReply(
        conversationID _: UUID,
        request _: MessageStreamRequest
    ) -> AsyncThrowingStream<QueryStreamEvent, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private final class StubMemoryClient: MemoryClientProtocol, Sendable {
    private let memories: [UUID: MemoryDTO]
    // Reads are issued concurrently from a `TaskGroup`, so the call counter has
    // to be safe off the main actor. `OSAllocatedUnfairLock.withLock` is the
    // async-safe form; `NSLock.lock()` is unavailable from an async context.
    private let calls = OSAllocatedUnfairLock(initialState: 0)

    var getCallCount: Int { calls.withLock { $0 } }

    init(memories: [UUID: MemoryDTO]) {
        self.memories = memories
    }

    func get(id: UUID) async throws -> MemoryDTO {
        calls.withLock { $0 += 1 }
        guard let memory = memories[id] else { throw APIError.unauthorized }
        return memory
    }

    func upsert(_: MemoryUpsertRequest) async throws -> MemoryUpsertResponse { throw APIError.unauthorized }
    func patch(id _: UUID, _: MemoryPatchRequest) async throws -> MemoryDTO { throw APIError.unauthorized }
    func list(limit _: Int, offset _: Int) async throws -> MemoryListResponse { throw APIError.unauthorized }
    func search(_: MemorySearchRequest) async throws -> MemorySearchResponse { throw APIError.unauthorized }
    func delete(id _: UUID) async throws { throw APIError.unauthorized }
}

private final class FailingMemoryClient: MemoryClientProtocol, @unchecked Sendable {
    func upsert(_: MemoryUpsertRequest) async throws -> MemoryUpsertResponse { throw APIError.unauthorized }
    func get(id _: UUID) async throws -> MemoryDTO { throw APIError.unauthorized }
    func patch(id _: UUID, _: MemoryPatchRequest) async throws -> MemoryDTO { throw APIError.unauthorized }
    func list(limit _: Int, offset _: Int) async throws -> MemoryListResponse { throw APIError.unauthorized }
    func search(_: MemorySearchRequest) async throws -> MemorySearchResponse { throw APIError.unauthorized }
    func delete(id _: UUID) async throws { throw APIError.unauthorized }
}

private struct FailingChatClient: ChatClientProtocol {
    func complete(_: ChatRequest) async throws -> ChatResponse { throw APIError.unauthorized }
}
