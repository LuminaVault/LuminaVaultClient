// LuminaVaultClient/LuminaVaultClientTests/ChatObservationScopeTests.swift
//
// SwiftUI re-renders a view when any property it *read during its body* is
// written. Two hot paths in chat were violating that on the widest possible
// scope:
//
//   * `PendingAssistantRow(text: viewModel.displayedAssistant)` read the
//     streaming text in `ChatView`'s body, so all ~62 typewriter ticks per
//     second invalidated the whole screen, `bottomBar`'s ten subviews included.
//   * The composer `TextField` bound to `viewModel.composer`, so a keystroke
//     marked the object that owns `messages` as changed.
//
// `Self._printChanges()` shows this at runtime but proves nothing in CI. These
// tests assert the same property directly against the Observation runtime:
// tracking the transcript's properties must not fire when only streaming text
// or only the draft changes.
@testable import LuminaVaultClient
import Observation
import XCTest

@MainActor
final class ChatObservationScopeTests: XCTestCase {
    private func makeViewModel() -> ChatViewModel {
        ChatViewModel(
            conversationsClient: InertConversationsClient(),
            chatClient: InertChatClient(),
            memoryClient: InertMemoryClient(),
            historyStore: nil
        )
    }

    /// Runs `body`, tracking whatever it reads, and reports whether `mutate`
    /// caused a change notification for any of those reads.
    private func didNotify(reading body: @escaping () -> Void, mutate: () -> Void) -> Bool {
        final class Box: @unchecked Sendable { var fired = false }
        let box = Box()
        withObservationTracking(body) { box.fired = true }
        mutate()
        return box.fired
    }

    // MARK: - Streaming text

    func testStreamingTextDoesNotInvalidateTheTranscriptScope() {
        let vm = makeViewModel()
        vm.messages = [.init(role: .user, content: "hi")]

        // Stand-in for `ChatView`'s body after the extraction: it reads the
        // transcript and the composer-independent flags, but never the
        // streaming text.
        let fired = didNotify {
            _ = vm.messages.count
            _ = vm.phase
            _ = vm.canAcceptSend
        } mutate: {
            vm.displayedAssistant = "a token arrived"
        }

        XCTAssertFalse(fired, "a typewriter tick must not invalidate the transcript's scope")
    }

    /// `pendingAssistant` is appended on every arriving SSE token, so reading
    /// it from `ChatView`'s body re-invalidated the whole screen per token —
    /// the same defect as the 62Hz `displayedAssistant` read, one layer down.
    /// The transcript reads the derived `hasPendingTurn` flag instead, which
    /// is only written when the answer starts or ends.
    func testArrivingTokensDoNotInvalidateTheTranscriptScope() {
        let vm = makeViewModel()
        vm.phase = .streaming

        let fired = didNotify {
            _ = vm.messages.count
            _ = vm.hasPendingTurn
        } mutate: {
            vm.pendingAssistant += "another token"
        }

        XCTAssertFalse(fired, "an arriving token must not invalidate the transcript's scope")
    }

    func testHasPendingTurnTracksTheStreamLifecycle() {
        let vm = makeViewModel()
        XCTAssertFalse(vm.hasPendingTurn)

        vm.phase = .streaming
        XCTAssertTrue(vm.hasPendingTurn, "a started stream owns a pending row before any token lands")

        vm.phase = .idle
        XCTAssertFalse(vm.hasPendingTurn)
    }

    func testStreamingTextDoesInvalidateAScopeThatReadsIt() {
        let vm = makeViewModel()

        // Stand-in for `StreamingAssistantRow`'s body — this one *should* fire.
        let fired = didNotify {
            _ = vm.displayedAssistant
        } mutate: {
            vm.displayedAssistant = "a token arrived"
        }

        XCTAssertTrue(fired, "the streaming row is the one view that must redraw per tick")
    }

    // MARK: - Composer

    func testKeystrokeDoesNotInvalidateTheTranscriptScope() {
        let vm = makeViewModel()
        vm.messages = [.init(role: .user, content: "hi")]

        let fired = didNotify {
            _ = vm.messages.count
            _ = vm.phase
        } mutate: {
            vm.composerModel.text = "typing…"
        }

        XCTAssertFalse(fired, "a keystroke must not dirty the object that owns `messages`")
    }

    func testKeystrokeInvalidatesTheComposerScope() {
        let vm = makeViewModel()

        let fired = didNotify {
            _ = vm.composerModel.text
        } mutate: {
            vm.composerModel.text = "typing…"
        }

        XCTAssertTrue(fired)
    }

    func testStagedReferencesAlsoLiveInTheComposerScope() {
        let vm = makeViewModel()

        let fired = didNotify {
            _ = vm.messages.count
        } mutate: {
            vm.attach(name: "note.md", text: "body")
        }

        XCTAssertFalse(fired, "staging a reference must not invalidate the transcript")
    }

    // MARK: - Forwarding stays intact

    func testComposerForwardsToTheComposerModel() {
        let vm = makeViewModel()
        vm.composer = "through the facade"
        XCTAssertEqual(vm.composerModel.text, "through the facade")

        vm.composerModel.text = "and back"
        XCTAssertEqual(vm.composer, "and back")
    }

    func testStagedReferencesForwardToTheComposerModel() {
        let vm = makeViewModel()
        vm.attach(name: "a.md", text: "one")
        XCTAssertEqual(vm.composerModel.stagedReferences.map(\.name), ["a.md"])
        XCTAssertEqual(vm.stagedReferences.map(\.name), ["a.md"])

        vm.clearAttachment()
        XCTAssertTrue(vm.composerModel.stagedReferences.isEmpty)
    }

    func testCanSendCombinesDraftContentAndStreamState() {
        let vm = makeViewModel()
        XCTAssertFalse(vm.canSend, "an empty draft can't be sent")
        XCTAssertTrue(vm.canAcceptSend)

        vm.composer = "  \n "
        XCTAssertFalse(vm.canSend, "whitespace is not content")

        vm.composer = "real text"
        XCTAssertTrue(vm.canSend)

        vm.phase = .streaming
        XCTAssertFalse(vm.canSend, "no send while streaming")
        XCTAssertFalse(vm.canAcceptSend)
    }
}

// MARK: - Inert clients

private struct InertConversationsClient: ConversationsClientProtocol {
    func create(_: ConversationCreateRequest) async throws -> ConversationDTO {
        throw APIError.unauthorized
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
        AsyncThrowingStream { $0.finish() }
    }
}

private struct InertChatClient: ChatClientProtocol {
    func complete(_: ChatRequest) async throws -> ChatResponse {
        throw APIError.unauthorized
    }
}

private struct InertMemoryClient: MemoryClientProtocol {
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
