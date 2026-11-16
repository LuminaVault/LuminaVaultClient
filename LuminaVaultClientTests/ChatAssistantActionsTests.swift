// LuminaVaultClientTests/ChatAssistantActionsTests.swift
//
// What the assistant did in the app on a chat turn: chips, confirm cards, the
// reload they ask for and the screen they open.
import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

// Every case is `async`, including the ones that await nothing: a synchronous
// case in a `@MainActor` XCTestCase that lets a main-actor object go aborts in
// the object's deinit on Xcode 26.2.
@MainActor
final class ChatAssistantActionsTests: XCTestCase {
    private let space = UUID()

    private func done(_ summary: String = "Created the space Health", change: AssistantChangeDTO = .created) -> AssistantActionDTO {
        AssistantActionDTO(
            id: UUID(), kind: .done, summary: summary,
            resource: AssistantResourceDTO(kind: .space, id: space, change: change)
        )
    }

    private func ask(_ summary: String = "Delete the space Recipes?") -> AssistantActionDTO {
        AssistantActionDTO(
            id: UUID(), kind: .needsConfirm, summary: summary,
            resource: AssistantResourceDTO(kind: .space, id: space, change: .deleted)
        )
    }

    private func openSpace() -> AssistantActionDTO {
        AssistantActionDTO(id: UUID(), kind: .openScreen, summary: "Opening Health", screen: .space, spaceID: space)
    }

    /// A store that records what it asks the shell to do.
    private func store(_ client: (any AssistantActionsClientProtocol)? = FixedActions()) -> (ChatAssistantActions, Recorder) {
        let store = ChatAssistantActions(client: client)
        let recorder = Recorder()
        store.onAppChange = { recorder.changes.append($0) }
        store.onOpenScreen = { recorder.routes.append($0) }
        return (store, recorder)
    }

    // MARK: - Frames

    func testADoneActionShowsAChipAndAsksForAReloadAtOnce() async {
        let (store, recorder) = store()
        let action = done()

        store.receive(action)

        XCTAssertEqual(store.actions(anchoredTo: nil, known: []), [action])
        XCTAssertEqual(recorder.changes, [AssistantResourceDTO(kind: .space, id: space, change: .created)])
    }

    func testTheSameFrameTwiceIsOneAction() async {
        let (store, recorder) = store()
        let action = done()

        store.receive(action)
        store.receive(action)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(recorder.changes.count, 1)
    }

    func testAConfirmCardChangesNothingUntilItIsConfirmed() async {
        let (store, recorder) = store()

        store.receive(ask())

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertTrue(recorder.changes.isEmpty, "nothing was deleted yet")
    }

    func testKindsChatDoesNotDrawAreDropped() async {
        let (store, recorder) = store()

        store.receive(AssistantActionDTO(id: UUID(), kind: .needsPermission, summary: "Allow Calendar"))
        store.receive(AssistantActionDTO(id: UUID(), kind: .unknown, summary: "?"))

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(recorder.changes.isEmpty)
    }

    // MARK: - Where they sit

    func testActionsMoveUnderTheReplyWhenTheTurnEnds() async {
        let (store, _) = store()
        let first = done()
        let reply = UUID()
        store.receive(first)

        store.finishTurn(anchoredTo: reply)

        XCTAssertEqual(store.actions(anchoredTo: reply, known: [reply]), [first])
        XCTAssertTrue(store.actions(anchoredTo: nil, known: [reply]).isEmpty)
        XCTAssertTrue(store.actions(anchoredTo: UUID(), known: [reply]).isEmpty)
    }

    func testALaterTurnDoesNotMoveAnEarlierTurnsActions() async {
        let (store, _) = store()
        let first = done(), second = done("Renamed the space", change: .updated)
        let firstReply = UUID(), secondReply = UUID()
        store.receive(first)
        store.finishTurn(anchoredTo: firstReply)
        store.receive(second)

        store.finishTurn(anchoredTo: secondReply)

        XCTAssertEqual(store.actions(anchoredTo: firstReply, known: [firstReply, secondReply]), [first])
        XCTAssertEqual(store.actions(anchoredTo: secondReply, known: [firstReply, secondReply]), [second])
    }

    func testAnActionWhoseMessageWasTrimmedStillShows() async {
        let (store, _) = store()
        let action = done()
        let reply = UUID()
        store.receive(action)
        store.finishTurn(anchoredTo: reply)

        XCTAssertEqual(store.actions(anchoredTo: nil, known: []), [action], "the reply was rewound away")
    }

    // MARK: - Confirm cards

    func testACardWaitsForTheReplyToEnd() async {
        let (store, _) = store()
        let action = ask()
        store.isStreaming = true
        store.receive(action)

        XCTAssertEqual(store.confirmState(for: action), .awaitingReply)
        XCTAssertFalse(store.confirmState(for: action).buttonsEnabled)

        store.finishTurn(anchoredTo: UUID())

        XCTAssertEqual(store.confirmState(for: action), .ask(error: nil))
    }

    func testConfirmingRunsTheChangeAndAsksForAReload() async {
        let (store, recorder) = store(FixedActions(confirm: .init(status: .confirmed, message: "Deleted the space Recipes.")))
        let action = ask()
        store.receive(action)
        store.finishTurn(anchoredTo: UUID())

        await store.confirm(action)

        XCTAssertEqual(
            store.confirmState(for: action),
            .finished(.init(status: .confirmed, message: "Deleted the space Recipes."))
        )
        XCTAssertEqual(recorder.changes, [AssistantResourceDTO(kind: .space, id: space, change: .deleted)])
    }

    func testAConfirmTheServerDidNotCarryOutReloadsNothing() async {
        for status in [AssistantActionStatusDTO.failed, .expired, .alreadyResolved, .unknown] {
            let (store, recorder) = store(FixedActions(confirm: .init(status: status, message: "No.")))
            let action = ask()
            store.receive(action)
            store.finishTurn(anchoredTo: UUID())

            await store.confirm(action)

            XCTAssertTrue(recorder.changes.isEmpty, "\(status)")
            XCTAssertEqual(store.confirmState(for: action), .finished(.init(status: status, message: "No.")))
        }
    }

    func testCancellingReloadsNothing() async {
        let (store, recorder) = store()
        let action = ask()
        store.receive(action)
        store.finishTurn(anchoredTo: UUID())

        await store.cancel(action)

        XCTAssertEqual(store.confirmState(for: action), .finished(.init(status: .cancelled, message: "Cancelled.")))
        XCTAssertTrue(recorder.changes.isEmpty)
    }

    func testAFailedConfirmLeavesTheCardAnswerable() async {
        let (store, recorder) = store(FixedActions(error: APIError.httpError(statusCode: 403, data: Data())))
        let action = ask()
        store.receive(action)
        store.finishTurn(anchoredTo: UUID())

        await store.confirm(action)

        XCTAssertEqual(store.confirmState(for: action), .ask(error: QuickAssistantModel.noWriteAccessMessage))
        XCTAssertTrue(store.confirmState(for: action).buttonsEnabled)
        XCTAssertTrue(recorder.changes.isEmpty)
    }

    func testAnAnswerForAThreadTheUserLeftIsDropped() async {
        let gate = GatedActions()
        let (store, recorder) = store(gate)
        let action = ask()
        store.receive(action)
        store.finishTurn(anchoredTo: UUID())
        let tap = Task { await store.confirm(action) }
        for _ in 0 ..< 400 where !store.resolving.contains(action.id) { try? await Task.sleep(for: .milliseconds(5)) }

        store.reset()
        gate.release()
        await tap.value

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.resolutions.isEmpty)
        XCTAssertTrue(recorder.changes.isEmpty, "the other thread's screens were not asked to reload")
    }

    // MARK: - Opening a screen

    func testAScreenIsOpenedWhenTheTurnEnds() async {
        let (store, recorder) = store()
        store.receive(openSpace())
        XCTAssertTrue(recorder.routes.isEmpty, "not while the reply is still arriving")

        store.finishTurn(anchoredTo: UUID())

        XCTAssertEqual(recorder.routes, [.space(id: space)])
        XCTAssertTrue(store.entries.isEmpty, "an opened screen leaves no chip")
    }

    func testAScreenIsNotOpenedOverACardThatStillNeedsAnAnswer() async {
        let (store, recorder) = store()
        store.receive(ask())
        store.receive(openSpace())

        store.finishTurn(anchoredTo: UUID())

        XCTAssertTrue(recorder.routes.isEmpty)
    }

    func testAFailedTurnOpensNothingButKeepsWhatAlreadyHappened() async {
        let (store, recorder) = store()
        let action = done()
        let last = UUID()
        store.isStreaming = true
        store.receive(action)
        store.receive(openSpace())

        store.abandonTurn(anchoredTo: last)

        XCTAssertTrue(recorder.routes.isEmpty)
        XCTAssertEqual(store.actions(anchoredTo: last, known: [last]), [action])
        XCTAssertFalse(store.isStreaming)
    }

    func testAScreenFromOneTurnIsNotOpenedByTheNext() async {
        let (store, recorder) = store()
        store.receive(openSpace())
        store.abandonTurn(anchoredTo: nil)

        store.finishTurn(anchoredTo: UUID())

        XCTAssertTrue(recorder.routes.isEmpty)
    }

    // MARK: - Routes and styling

    func testASpaceScreenRoutesToThatSpace() async {
        XCTAssertEqual(QuickAssistantRoute.resolve(openSpace()), .space(id: space))
        XCTAssertEqual(QuickAssistantRoute.resolve(.space, memoryID: nil, spaceID: nil), .tab(.workspaces))
        XCTAssertEqual(QuickAssistantRoute.resolve(.spaces, memoryID: nil, spaceID: space), .tab(.workspaces))
    }

    func testADeleteCardIsDestructiveAndOtherChangesAreNot() async {
        XCTAssertTrue(ask().isDestructive)
        let update = AssistantActionDTO(
            id: UUID(), kind: .needsConfirm, summary: "Change this memory?",
            resource: AssistantResourceDTO(kind: .memory, id: UUID(), change: .updated)
        )
        XCTAssertFalse(update.isDestructive)
        XCTAssertFalse(done(change: .deleted).isDestructive, "a chip is not a question")
    }

    // MARK: - What reloads

    func testEachKindOfChangeReloadsTheScreensThatShowIt() async {
        let app = AppState()
        let before = (app.spacesRevision, app.vaultFilesRevision, app.memoriesRevision)

        app.assistantChanged(AssistantResourceDTO(kind: .space, id: space, change: .created))
        XCTAssertEqual(app.spacesRevision, before.0 + 1)
        XCTAssertEqual(app.vaultFilesRevision, before.1 + 1, "a space's notes move with it")
        XCTAssertEqual(app.memoriesRevision, before.2)

        app.assistantChanged(AssistantResourceDTO(kind: .vaultFile, change: .moved))
        XCTAssertEqual(app.spacesRevision, before.0 + 1)
        XCTAssertEqual(app.vaultFilesRevision, before.1 + 2)
        XCTAssertEqual(app.memoriesRevision, before.2)

        app.assistantChanged(AssistantResourceDTO(kind: .vaultFile, change: .deleted))
        XCTAssertEqual(app.vaultFilesRevision, before.1 + 3)
        XCTAssertEqual(app.memoriesRevision, before.2 + 1, "a deleted note takes its memories with it")

        app.assistantChanged(AssistantResourceDTO(kind: .memory, id: UUID(), change: .updated))
        XCTAssertEqual(app.memoriesRevision, before.2 + 2)
        XCTAssertEqual(app.vaultFilesRevision, before.1 + 3)
    }

    // MARK: - Through the chat view model

    func testAnActionFrameOnAChatTurnLandsUnderItsReply() async throws {
        let action = done()
        let vm = ChatViewModel(
            conversationsClient: ScriptedConversations(events: [
                .assistantAction(action), .token("I created the Health space."), .done,
            ]),
            chatClient: NoChat(),
            memoryClient: NoMemory(),
            historyStore: nil
        )
        vm.transport = .memoryGrounded
        var changes: [AssistantResourceDTO] = []
        vm.assistantActions.onAppChange = { changes.append($0) }

        vm.composer = "create a space called Health"
        vm.send()
        await waitUntil("the turn to end") { vm.phase == .idle && vm.messages.last?.role == .assistant }

        let reply = try XCTUnwrap(vm.messages.last)
        XCTAssertEqual(reply.content, "I created the Health space.")
        XCTAssertEqual(vm.assistantActions.actions(anchoredTo: reply.id, known: Set(vm.messages.map(\.id))), [action])
        XCTAssertEqual(changes, [AssistantResourceDTO(kind: .space, id: space, change: .created)])
        XCTAssertFalse(vm.assistantActions.isStreaming)
    }

    func testANewThreadStartsWithNoActions() async {
        let vm = ChatViewModel(
            conversationsClient: ScriptedConversations(events: [.assistantAction(done()), .token("Done."), .done]),
            chatClient: NoChat(),
            memoryClient: NoMemory(),
            historyStore: nil
        )
        vm.transport = .memoryGrounded
        vm.composer = "create a space called Health"
        vm.send()
        await waitUntil("the turn to end") { vm.phase == .idle && vm.messages.last?.role == .assistant }

        vm.reset()

        XCTAssertTrue(vm.assistantActions.entries.isEmpty)
    }
}

// MARK: - Doubles

@MainActor
private final class Recorder {
    var changes: [AssistantResourceDTO] = []
    var routes: [QuickAssistantRoute] = []
}

private struct FixedActions: AssistantActionsClientProtocol {
    var confirm: AssistantActionResolutionDTO = .init(status: .confirmed, message: "Done.")
    var error: (any Error)?

    func confirm(_: UUID) async throws -> AssistantActionResolutionDTO {
        if let error { throw error }
        return confirm
    }

    func cancel(_: UUID) async throws -> AssistantActionResolutionDTO {
        if let error { throw error }
        return .init(status: .cancelled, message: "Cancelled.")
    }
}

private final class ScriptedConversations: ConversationsClientProtocol, @unchecked Sendable {
    // @unchecked: `events` is set once at init and only read.
    let events: [QueryStreamEvent]
    init(events: [QueryStreamEvent]) { self.events = events }

    func create(_: ConversationCreateRequest) async throws -> ConversationDTO {
        ConversationDTO(id: UUID(), title: "", createdAt: Date(), updatedAt: Date())
    }

    func list() async throws -> ConversationListResponse { ConversationListResponse(conversations: []) }
    func get(_: UUID) async throws -> ConversationDetailResponse { throw APIError.unauthorized }
    func delete(_: UUID) async throws {}
    func streamReply(
        conversationID _: UUID,
        request _: MessageStreamRequest
    ) -> AsyncThrowingStream<QueryStreamEvent, any Error> {
        let events = events
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

private struct NoChat: ChatClientProtocol {
    func complete(_: ChatRequest) async throws -> ChatResponse { throw APIError.unauthorized }
}

private struct NoMemory: MemoryClientProtocol {
    func upsert(_: MemoryUpsertRequest) async throws -> MemoryUpsertResponse { throw APIError.unauthorized }
    func get(id _: UUID) async throws -> MemoryDTO { throw APIError.unauthorized }
    func patch(id _: UUID, _: MemoryPatchRequest) async throws -> MemoryDTO { throw APIError.unauthorized }
    func list(limit _: Int, offset _: Int) async throws -> MemoryListResponse { throw APIError.unauthorized }
    func search(_: MemorySearchRequest) async throws -> MemorySearchResponse { throw APIError.unauthorized }
    func delete(id _: UUID) async throws { throw APIError.unauthorized }
}
