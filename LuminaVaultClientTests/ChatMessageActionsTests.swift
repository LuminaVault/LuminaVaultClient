// LuminaVaultClient/LuminaVaultClientTests/ChatMessageActionsTests.swift
//
// Regenerate and edit-and-resend both trim the transcript, so the thing worth
// pinning down is exactly *how much* they trim and when. Getting either wrong
// destroys turns the user still wanted.
@testable import LuminaVaultClient
import LuminaVaultShared
import XCTest

@MainActor
final class ChatMessageActionsTests: XCTestCase {
    private func makeViewModel() -> ChatViewModel {
        ChatViewModel(
            conversationsClient: RecordingConversationsClient(),
            chatClient: RecordingChatClient(),
            memoryClient: RefusingMemoryClient(),
            historyStore: nil
        )
    }

    /// user → assistant → user → assistant
    private func seedTwoExchanges(_ vm: ChatViewModel) -> [ChatViewModel.Message] {
        let messages: [ChatViewModel.Message] = [
            .init(role: .user, content: "first question"),
            .init(role: .assistant, content: "first answer"),
            .init(role: .user, content: "second question"),
            .init(role: .assistant, content: "second answer"),
        ]
        vm.messages = messages
        return messages
    }

    // MARK: - Regenerate

    func testRegenerateTrimsBackToThePromptAndResends() async throws {
        let vm = makeViewModel()
        let seeded = seedTwoExchanges(vm)

        vm.regenerate(seeded[3])
        try await Task.sleep(for: .milliseconds(150))

        // The first exchange survives; the second is re-asked from scratch.
        XCTAssertEqual(
            vm.messages.map(\.content).prefix(3),
            ["first question", "first answer", "second question"]
        )
        XCTAssertEqual(vm.composer, "", "the prompt is consumed by the resend, not left in the draft")
    }

    func testRegenerateOnAnEarlierTurnDiscardsEverythingAfterIt() async throws {
        let vm = makeViewModel()
        let seeded = seedTwoExchanges(vm)

        vm.regenerate(seeded[1])
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(vm.messages.first?.content, "first question")
        XCTAssertFalse(
            vm.messages.contains { $0.content == "second question" },
            "regenerating an earlier answer cannot leave later turns orphaned above it"
        )
    }

    func testRegenerateIgnoresUserTurns() {
        let vm = makeViewModel()
        let seeded = seedTwoExchanges(vm)

        vm.regenerate(seeded[2])

        XCTAssertEqual(vm.messages.count, 4, "there is nothing to regenerate about a user turn")
    }

    func testRegenerateIsRefusedWhileStreaming() {
        let vm = makeViewModel()
        let seeded = seedTwoExchanges(vm)
        vm.phase = .streaming

        vm.regenerate(seeded[3])

        XCTAssertEqual(
            vm.messages.count,
            4,
            "the stop button owns this intent mid-stream; racing finalize would drop the turn"
        )
    }

    func testRegenerateWithNoPrecedingUserTurnIsANoOp() {
        let vm = makeViewModel()
        let orphan = ChatViewModel.Message(role: .assistant, content: "unprompted")
        vm.messages = [orphan]

        vm.regenerate(orphan)

        XCTAssertEqual(vm.messages.count, 1)
    }

    // MARK: - Edit and resend

    func testBeginEditLoadsTheTurnWithoutTrimmingAnything() {
        let vm = makeViewModel()
        let seeded = seedTwoExchanges(vm)

        vm.beginEdit(seeded[2])

        XCTAssertEqual(vm.composer, "second question")
        XCTAssertEqual(vm.composerModel.editingMessageID, seeded[2].id)
        XCTAssertEqual(vm.messages.count, 4, "nothing is destroyed until the edit is actually sent")
    }

    func testCancellingAnEditLeavesTheTranscriptIntact() {
        let vm = makeViewModel()
        let seeded = seedTwoExchanges(vm)

        vm.beginEdit(seeded[2])
        vm.cancelEdit()

        XCTAssertEqual(vm.messages.count, 4)
        XCTAssertEqual(vm.composer, "")
        XCTAssertFalse(vm.composerModel.isEditing)
    }

    func testSendingAnEditTrimsFromTheEditedTurn() async throws {
        let vm = makeViewModel()
        let seeded = seedTwoExchanges(vm)

        vm.beginEdit(seeded[2])
        vm.composer = "second question, rephrased"
        vm.send()
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(
            vm.messages.map(\.content).prefix(3),
            ["first question", "first answer", "second question, rephrased"]
        )
        XCTAssertFalse(vm.composerModel.isEditing, "the edit is finished once it's sent")
    }

    func testBeginEditIgnoresAssistantTurns() {
        let vm = makeViewModel()
        let seeded = seedTwoExchanges(vm)

        vm.beginEdit(seeded[3])

        XCTAssertEqual(vm.composer, "", "only the user's own words are editable")
        XCTAssertFalse(vm.composerModel.isEditing)
    }

    func testBeginEditIsRefusedWhileStreaming() {
        let vm = makeViewModel()
        let seeded = seedTwoExchanges(vm)
        vm.phase = .streaming

        vm.beginEdit(seeded[2])

        XCTAssertFalse(vm.composerModel.isEditing)
    }

    // MARK: - Shared trim behaviour

    func testRewindStillTrimsFromTheGivenTurn() {
        let vm = makeViewModel()
        let seeded = seedTwoExchanges(vm)

        vm.rewind(to: seeded[2])

        XCTAssertEqual(vm.messages.map(\.content), ["first question", "first answer"])
    }

    func testTrimClearsProposalsThatDescribedTheDiscardedTurns() {
        let vm = makeViewModel()
        let seeded = seedTwoExchanges(vm)
        vm.jobProposal = JobProposalDTO(isJob: true, title: "Daily digest", cron: "0 9 * * *")

        vm.rewind(to: seeded[2])

        XCTAssertNil(
            vm.jobProposal,
            "a proposal derived from a discarded turn would otherwise be attributed to the wrong message"
        )
    }
}

// MARK: - Stubs

private final class RecordingConversationsClient: ConversationsClientProtocol, @unchecked Sendable {
    func create(_: ConversationCreateRequest) async throws -> ConversationDTO {
        ConversationDTO(id: UUID(), title: "t", spaceId: nil, createdAt: Date(), updatedAt: Date())
    }

    func list() async throws -> ConversationListResponse {
        ConversationListResponse(conversations: [])
    }

    func get(_: UUID) async throws -> ConversationDetailResponse {
        throw APIError.unauthorized
    }

    func delete(_: UUID) async throws {}

    func streamReply(
        conversationID _: UUID,
        request _: MessageStreamRequest
    ) -> AsyncThrowingStream<QueryStreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.token("regenerated"))
            continuation.yield(.done)
            continuation.finish()
        }
    }
}

private struct RecordingChatClient: ChatClientProtocol {
    func complete(_: ChatRequest) async throws -> ChatResponse {
        throw APIError.unauthorized
    }
}

private struct RefusingMemoryClient: MemoryClientProtocol {
    func upsert(_: MemoryUpsertRequest) async throws -> MemoryUpsertResponse {
        throw APIError.unauthorized
    }

    func get(id _: UUID) async throws -> MemoryDTO {
        throw APIError.unauthorized
    }

    func patch(id _: UUID, _: MemoryPatchRequest) async throws -> MemoryDTO {
        throw APIError.unauthorized
    }

    func list(limit _: Int, offset _: Int) async throws -> MemoryListResponse {
        throw APIError.unauthorized
    }

    func search(_: MemorySearchRequest) async throws -> MemorySearchResponse {
        throw APIError.unauthorized
    }

    func delete(id _: UUID) async throws {
        throw APIError.unauthorized
    }
}
