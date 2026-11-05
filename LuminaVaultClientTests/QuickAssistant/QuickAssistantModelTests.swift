// LuminaVaultClient/LuminaVaultClientTests/QuickAssistant/QuickAssistantModelTests.swift
//
// Quick Assistant model: the hybrid-execution gate, one conversation per
// card session, action frames as the only source of actions, and the
// confirm / cancel / reset edge cases (send while streaming, reset mid-stream,
// network failure on confirm, expired action).
@testable import LuminaVaultClient
import LuminaVaultShared
import os
import XCTest

@MainActor
final class QuickAssistantModelTests: XCTestCase {
    private var stub: StubConversations!
    private var actionsStub: StubActions!
    private var speech: StubSpeech!
    private var settings: HybridExecutionSettingsStore!
    private var online = true
    private var model: QuickAssistantModel!

    override func setUp() async throws {
        stub = StubConversations()
        actionsStub = StubActions()
        speech = StubSpeech()
        let suite = "QuickAssistantModelTests.\(UUID().uuidString)"
        settings = HybridExecutionSettingsStore(defaults: UserDefaults(suiteName: suite)!)
        settings.profile = .quality
        settings.cloudFallbackEnabled = true
        online = true
        model = QuickAssistantModel(
            conversations: stub,
            actions: actionsStub,
            settings: settings,
            synthesizer: speech,
            isOnline: { [unowned self] in self.online }
        )
    }

    private func send(_ text: String = "hi", viaVoice: Bool = false, tab: String = "home", space: UUID? = nil) async {
        await model.send(text, viaVoice: viaVoice, currentTab: tab, activeSpaceID: space)
    }

    private func confirmAction(expires: Date? = nil) -> AssistantActionDTO {
        AssistantActionDTO(id: UUID(), kind: .needsConfirm, summary: "Add reminder?", expiresAt: expires)
    }

    private func isBlocked(_ phase: QuickAssistantPhase) -> Bool {
        if case .blocked = phase { return true }
        return false
    }

    private func waitUntil(_ cond: @MainActor () -> Bool) async {
        for _ in 0 ..< 500 where !cond() { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(cond(), "condition never became true")
    }

    // MARK: - Gate

    func testPrivateProfileSendsNothing() async {
        settings.profile = .private
        await send()
        XCTAssertTrue(isBlocked(model.phase))
        XCTAssertEqual(stub.createCount, 0)
        XCTAssertEqual(stub.streamRequests.count, 0)
    }

    func testBalancedWithCloudFallbackOffSendsNothing() async {
        settings.profile = .balanced
        settings.cloudFallbackEnabled = false
        await send()
        XCTAssertTrue(isBlocked(model.phase))
        XCTAssertEqual(stub.streamRequests.count, 0)
    }

    func testQualitySends() async {
        stub.script = [.token("Hello"), .done]
        await send()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.reply, "Hello")
        XCTAssertEqual(stub.streamRequests.count, 1)
    }

    func testOfflineExplainsAndSendsNothing() async {
        online = false
        await send()
        guard case let .blocked(message) = model.phase else { return XCTFail("expected blocked, got \(model.phase)") }
        XCTAssertTrue(message.lowercased().contains("offline"), message)
        XCTAssertEqual(stub.createCount, 0)
        XCTAssertEqual(stub.streamRequests.count, 0)
    }

    func testEmptyTranscriptSendsNothing() async {
        await send("  \n ", viaVoice: true)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(stub.createCount, 0)
        XCTAssertEqual(stub.streamRequests.count, 0)
    }

    // MARK: - Conversation and request

    func testFirstSendCreatesConversationThenReuses() async {
        stub.script = [.done]
        await send("one")
        let first = model.conversationID
        await send("two")
        XCTAssertNotNil(first)
        XCTAssertEqual(model.conversationID, first)
        XCTAssertEqual(stub.createCount, 1)
        XCTAssertEqual(stub.streamRequests.count, 2)
    }

    func testRequestCarriesContext() async {
        stub.script = [.done]
        let space = UUID()
        await send("note this", tab: "home", space: space)
        let req = stub.streamRequests.first
        XCTAssertEqual(req?.content, "note this")
        XCTAssertEqual(req?.quickAssistant?.currentTab, "home")
        XCTAssertEqual(req?.quickAssistant?.activeSpaceID, space)
    }

    func testRequestCarriesTheDevicesTimeZone() async throws {
        let santiago = try XCTUnwrap(TimeZone(identifier: "America/Santiago"))
        model = QuickAssistantModel(
            conversations: stub,
            actions: actionsStub,
            settings: settings,
            synthesizer: speech,
            isOnline: { true },
            timeZone: { santiago }
        )
        stub.script = [.done]
        await send()
        XCTAssertEqual(stub.streamRequests.first?.quickAssistant?.timeZone, "America/Santiago")
    }

    func testTimeZoneDefaultsToTheDevicesCurrentZone() async {
        stub.script = [.done]
        await send()
        XCTAssertEqual(stub.streamRequests.first?.quickAssistant?.timeZone, TimeZone.current.identifier)
    }

    func testCurrentTabIsPassedThroughUnmapped() async {
        stub.script = [.done]
        for tab in ["home", "workspaces", "think", "brain", "reflect"] {
            await send("x", tab: tab)
            XCTAssertEqual(stub.streamRequests.last?.quickAssistant?.currentTab, tab)
        }
    }

    // MARK: - Frames

    func testOnlyFramesProduceActions() async {
        stub.script = [.token("Done! Reminder added"), .done]
        await send()
        XCTAssertEqual(model.reply, "Done! Reminder added")
        XCTAssertTrue(model.actions.isEmpty)
    }

    func testActionFrameIsKept() async {
        let action = confirmAction()
        stub.script = [.token("ok"), .assistantAction(action), .done]
        await send()
        XCTAssertEqual(model.actions, [action])
    }

    func testUnrecognizedFrameIsSkipped() async {
        stub.script = [.token("a"), .unrecognized("future_frame"), .token("b"), .done]
        await send()
        XCTAssertEqual(model.reply, "ab")
        XCTAssertEqual(model.phase, .idle)
    }

    func testStreamErrorFrameFails() async {
        stub.script = [.token("par"), .error("boom")]
        await send(viaVoice: true)
        XCTAssertEqual(model.phase, .failed("boom"))
        XCTAssertTrue(speech.spoken.isEmpty)
    }

    func testOpenScreenSetsPendingScreen() async {
        let memory = UUID()
        stub.script = [.assistantAction(AssistantActionDTO(id: UUID(), kind: .openScreen, summary: "Open", screen: .memory, memoryID: memory)), .done]
        await send()
        XCTAssertEqual(model.pendingScreen?.0, .memory)
        XCTAssertEqual(model.pendingScreen?.1, memory)
    }

    func testOpenScreenToleratesUnknownScreenAndMissingMemory() async {
        stub.script = [
            .assistantAction(AssistantActionDTO(id: UUID(), kind: .openScreen, summary: "Open", screen: .unknown)),
            .assistantAction(AssistantActionDTO(id: UUID(), kind: .openScreen, summary: "Open", screen: nil)),
            .assistantAction(AssistantActionDTO(id: UUID(), kind: .unknown, summary: "?")),
            .done,
        ]
        await send()
        XCTAssertEqual(model.actions.count, 3)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertNil(model.pendingScreen?.1)
    }

    // MARK: - Speech

    func testVoiceTurnSpeaksReplyTypedDoesNot() async {
        stub.script = [.token("Hi there"), .done]
        await send(viaVoice: false)
        XCTAssertTrue(speech.spoken.isEmpty)
        await send(viaVoice: true)
        XCTAssertEqual(speech.spoken, ["Hi there"])
    }

    func testVoiceNeedsConfirmSpeaksSummary() async {
        stub.script = [.token("Sure."), .assistantAction(confirmAction()), .done]
        await send(viaVoice: true)
        XCTAssertEqual(speech.spoken, ["Add reminder?"])
    }

    func testVoiceDoesNotSpeakBeforeStreamEnds() async {
        stub.holdStream = true
        let task = Task { await send(viaVoice: true) }
        await waitUntil { self.stub.streamRequests.count == 1 }
        stub.emit(.token("part"))
        await waitUntil { self.model.reply == "part" }
        XCTAssertTrue(speech.spoken.isEmpty)
        stub.emit(.done)
        stub.finish()
        await task.value
        XCTAssertEqual(speech.spoken, ["part"])
    }

    // MARK: - Confirm / cancel

    func testConfirmUpdatesActionFromResolution() async {
        let action = confirmAction()
        actionsStub.confirmResult = .success(.init(status: .alreadyResolved, message: "Already handled."))
        await model.confirm(action)
        XCTAssertEqual(model.resolutions[action.id]?.status, .alreadyResolved)
        XCTAssertEqual(model.resolutions[action.id]?.message, "Already handled.")
        XCTAssertEqual(actionsStub.confirmed, [action.id])
    }

    func testCancelUpdatesActionFromResolution() async {
        let action = confirmAction()
        actionsStub.cancelResult = .success(.init(status: .cancelled, message: "Cancelled."))
        await model.cancel(action)
        XCTAssertEqual(model.resolutions[action.id]?.status, .cancelled)
        XCTAssertEqual(actionsStub.cancelled, [action.id])
    }

    func testConfirmNetworkErrorKeepsActionActionable() async {
        let action = confirmAction()
        actionsStub.confirmResult = .failure(APIError.networkFailure(URLError(.notConnectedToInternet)))
        await model.confirm(action)
        XCTAssertNil(model.resolutions[action.id])
        XCTAssertNotNil(model.actionErrors[action.id])
        XCTAssertFalse(model.resolving.contains(action.id))
        // Retry succeeds from the same card.
        actionsStub.confirmResult = .success(.init(status: .confirmed, message: "Done."))
        await model.confirm(action)
        XCTAssertEqual(model.resolutions[action.id]?.status, .confirmed)
        XCTAssertNil(model.actionErrors[action.id])
    }

    func testConfirm404IsReadableMessage() async {
        let action = confirmAction()
        let body = Data(#"{"error":{"message":"not found"}}"#.utf8)
        actionsStub.confirmResult = .failure(APIError.httpError(statusCode: 404, data: body))
        await model.confirm(action)
        XCTAssertNil(model.resolutions[action.id])
        let message = model.actionErrors[action.id] ?? ""
        XCTAssertFalse(message.isEmpty)
        XCTAssertFalse(message.contains("404"))
    }

    func testExpiredActionIsStillSentAndServerMessageShown() async {
        let action = confirmAction(expires: Date(timeIntervalSinceNow: -3600))
        actionsStub.confirmResult = .success(.init(status: .expired, message: "That request expired."))
        await model.confirm(action)
        XCTAssertEqual(actionsStub.confirmed, [action.id])
        XCTAssertEqual(model.resolutions[action.id]?.status, .expired)
        XCTAssertEqual(model.resolutions[action.id]?.message, "That request expired.")
    }

    // MARK: - Send while streaming / reset

    func testSendWhileStreamingIsRefused() async {
        stub.holdStream = true
        let first = Task { await send("first") }
        await waitUntil { self.stub.streamRequests.count == 1 }
        XCTAssertEqual(model.phase, .sending)
        await send("second")
        XCTAssertEqual(stub.streamRequests.count, 1)
        XCTAssertEqual(stub.createCount, 1)
        stub.emit(.token("one"))
        stub.emit(.done)
        stub.finish()
        await first.value
        XCTAssertEqual(model.reply, "one")
        XCTAssertEqual(model.phase, .idle)
    }

    func testResetClearsConversation() async {
        stub.script = [.token("x"), .assistantAction(confirmAction()), .done]
        await send()
        let first = model.conversationID
        model.reset()
        XCTAssertNil(model.conversationID)
        XCTAssertEqual(model.reply, "")
        XCTAssertTrue(model.actions.isEmpty)
        XCTAssertNil(model.pendingScreen)
        XCTAssertEqual(model.phase, .idle)
        await send()
        XCTAssertEqual(stub.createCount, 2)
        XCTAssertNotEqual(model.conversationID, first)
    }

    func testResetDuringStreamIgnoresLaterFrames() async {
        stub.holdStream = true
        let task = Task { await send(viaVoice: true) }
        await waitUntil { self.stub.streamRequests.count == 1 }
        stub.emit(.token("early"))
        await waitUntil { self.model.reply == "early" }
        model.reset()
        stub.emit(.token("late"))
        stub.emit(.assistantAction(confirmAction()))
        stub.emit(.assistantAction(AssistantActionDTO(id: UUID(), kind: .openScreen, summary: "o", screen: .brain)))
        stub.emit(.done)
        stub.finish()
        await task.value
        XCTAssertEqual(model.reply, "")
        XCTAssertTrue(model.actions.isEmpty)
        XCTAssertNil(model.pendingScreen)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(speech.spoken.isEmpty)
    }

    func testResetStopsSpeech() async {
        model.reset()
        XCTAssertEqual(speech.stopCount, 1)
    }

    func testResetWhileCreatingConversationDoesNotAdoptIt() async {
        stub.holdCreate = true
        let task = Task { await send() }
        await waitUntil { self.stub.createCount == 1 }
        model.reset()
        stub.releaseCreate()
        await task.value
        XCTAssertNil(model.conversationID)
        XCTAssertEqual(stub.streamRequests.count, 0)
    }

    // MARK: - Fix round 1

    func testBlockedMessagesAreDistinctAndNameSettings() async {
        settings.profile = .private
        await send()
        let privateMsg = model.phase
        settings.profile = .balanced
        settings.cloudFallbackEnabled = false
        await send()
        let balancedMsg = model.phase
        settings.cloudFallbackEnabled = true
        online = false
        await send()
        let offlineMsg = model.phase
        let all = [privateMsg, balancedMsg, offlineMsg]
        XCTAssertEqual(Set(all.map { "\($0)" }).count, 3)
        for case let .blocked(text) in all.dropLast() {
            XCTAssertTrue(text.contains("Settings"), text)
        }
        if case let .blocked(text) = privateMsg { XCTAssertTrue(text.contains("Execution profile")) }
        if case let .blocked(text) = balancedMsg { XCTAssertTrue(text.contains("Allow cloud fallback")) }
    }

    func testBlockedSendClearsStaleCards() async {
        stub.script = [.token("old"), .assistantAction(confirmAction()), .done]
        await send()
        let stale = model.actions[0]
        actionsStub.confirmResult = .success(.init(status: .confirmed, message: "Done."))
        await model.confirm(stale)
        XCTAssertFalse(model.resolutions.isEmpty)
        settings.profile = .private
        await send()
        XCTAssertTrue(isBlocked(model.phase))
        XCTAssertEqual(model.reply, "")
        XCTAssertTrue(model.actions.isEmpty)
        XCTAssertTrue(model.resolutions.isEmpty)
    }

    func testSecondConfirmAfterResultSendsNothing() async {
        let action = confirmAction()
        await model.confirm(action)
        await model.confirm(action)
        await model.cancel(action)
        XCTAssertEqual(actionsStub.confirmed.count, 1)
        XCTAssertTrue(actionsStub.cancelled.isEmpty)
    }

    func testEmptyStreamFailsWithDidntAnswer() async {
        stub.script = [.done]
        await send(viaVoice: true)
        XCTAssertEqual(model.phase, .failed("Lumina didn't answer. Try again."))
        XCTAssertTrue(speech.spoken.isEmpty)
    }

    func testStreamClosedWithoutDoneKeepsTextFailsAndIsNotSpoken() async {
        stub.script = [.token("part")]
        await send(viaVoice: true)
        XCTAssertEqual(model.reply, "part")
        guard case .failed = model.phase else { return XCTFail("expected failed, got \(model.phase)") }
        XCTAssertTrue(speech.spoken.isEmpty)
    }

    func testThrownErrorMidStreamKeepsTextAndRetryReusesConversation() async {
        stub.script = [.token("part")]
        stub.scriptError = APIError.networkFailure(URLError(.networkConnectionLost))
        await send(viaVoice: true)
        XCTAssertEqual(model.reply, "part")
        guard case .failed = model.phase else { return XCTFail("expected failed, got \(model.phase)") }
        XCTAssertTrue(speech.spoken.isEmpty)
        let id = model.conversationID
        XCTAssertNotNil(id)
        stub.scriptError = nil
        stub.script = [.token("whole"), .done]
        await send()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.conversationID, id)
        XCTAssertEqual(stub.createCount, 1)
    }

    func testCreateFailureFailsAndRetryCreates() async {
        stub.failNextCreate(with: APIError.networkFailure(URLError(.notConnectedToInternet)))
        await send()
        guard case .failed = model.phase else { return XCTFail("expected failed, got \(model.phase)") }
        XCTAssertNil(model.conversationID)
        XCTAssertEqual(stub.streamRequests.count, 0)
        stub.script = [.token("ok"), .done]
        await send()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(stub.createCount, 2)
        XCTAssertNotNil(model.conversationID)
    }

    func testResetCancelsHeldStreamWithoutFailure() async {
        stub.holdStream = true
        let task = Task { await send(viaVoice: true) }
        await waitUntil { self.stub.streamRequests.count == 1 }
        model.reset()
        await waitUntil { self.stub.streamTerminated }
        await task.value
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.reply, "")
        XCTAssertTrue(speech.spoken.isEmpty)
    }

    /// iOS tearing down a stream throws `URLError.cancelled` though nobody asked.
    /// Idle would read as a finished answer; it is a cut-off one.
    func testUnrequestedCancellationShowsTheCutOffLine() async {
        stub.script = [.token("x")]
        stub.scriptError = APIError.networkFailure(URLError(.cancelled))
        await send(viaVoice: true)
        XCTAssertEqual(model.phase, .failed(QuickAssistantGate.cutOffMessage))
        XCTAssertEqual(model.reply, "x")
        XCTAssertTrue(speech.spoken.isEmpty)
    }

    func testUnrequestedBareURLCancellationShowsTheCutOffLine() async {
        stub.scriptError = URLError(.cancelled)
        await send()
        XCTAssertEqual(model.phase, .failed(QuickAssistantGate.cutOffMessage))
    }
}

// MARK: - Stubs

private final class StubConversations: ConversationsClientProtocol, @unchecked Sendable {
    // Every field lives behind the lock: the model calls in from the main
    // actor, the stream callbacks and test helpers from elsewhere.
    private struct State {
        var script: [QueryStreamEvent] = []
        var scriptError: (any Error)?
        var holdStream = false
        var holdCreate = false
        var createErrors: [any Error] = []
        var createCount = 0
        var requests: [MessageStreamRequest] = []
        var continuation: AsyncThrowingStream<QueryStreamEvent, any Error>.Continuation?
        var terminated = false
        var createGate: CheckedContinuation<Void, Never>?
        var createReleased = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var script: [QueryStreamEvent] {
        get { state.withLock { $0.script } }
        set { state.withLock { $0.script = newValue } }
    }

    /// Thrown after the scripted events instead of finishing cleanly.
    var scriptError: (any Error)? {
        get { state.withLock { $0.scriptError } }
        set { state.withLock { $0.scriptError = newValue } }
    }

    var holdStream: Bool {
        get { state.withLock { $0.holdStream } }
        set { state.withLock { $0.holdStream = newValue } }
    }

    var holdCreate: Bool {
        get { state.withLock { $0.holdCreate } }
        set { state.withLock { $0.holdCreate = newValue } }
    }

    func failNextCreate(with error: any Error) { state.withLock { $0.createErrors.append(error) } }
    var createCount: Int { state.withLock { $0.createCount } }
    var streamRequests: [MessageStreamRequest] { state.withLock { $0.requests } }
    var streamTerminated: Bool { state.withLock { $0.terminated } }

    func emit(_ event: QueryStreamEvent) { _ = state.withLock { $0.continuation }?.yield(event) }
    func finish() { state.withLock { $0.continuation }?.finish() }

    /// A latch, not a signal: safe whether it runs before or after `create`
    /// has parked its continuation.
    func releaseCreate() {
        let gate = state.withLock { s -> CheckedContinuation<Void, Never>? in
            s.createReleased = true
            defer { s.createGate = nil }
            return s.createGate
        }
        gate?.resume()
    }

    func create(_: ConversationCreateRequest) async throws -> ConversationDTO {
        let (hold, error) = state.withLock { s -> (Bool, (any Error)?) in
            s.createCount += 1
            return (s.holdCreate, s.createErrors.isEmpty ? nil : s.createErrors.removeFirst())
        }
        if hold {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let releasedAlready = state.withLock { s -> Bool in
                    if s.createReleased { return true }
                    s.createGate = cont
                    return false
                }
                if releasedAlready { cont.resume() }
            }
        }
        if let error { throw error }
        return ConversationDTO(id: UUID(), title: "", createdAt: Date(), updatedAt: Date())
    }

    func list() async throws -> ConversationListResponse { ConversationListResponse(conversations: []) }
    func get(_: UUID) async throws -> ConversationDetailResponse { throw APIError.unauthorized }
    func delete(_: UUID) async throws {}

    func streamReply(conversationID _: UUID, request: MessageStreamRequest) -> AsyncThrowingStream<QueryStreamEvent, any Error> {
        let (hold, events, failure) = state.withLock { ($0.holdStream, $0.script, $0.scriptError) }
        let stream = AsyncThrowingStream<QueryStreamEvent, any Error> { cont in
            if hold {
                cont.onTermination = { [state] _ in state.withLock { $0.terminated = true } }
                state.withLock { $0.continuation = cont }
            } else {
                for e in events { cont.yield(e) }
                if let failure { cont.finish(throwing: failure) } else { cont.finish() }
            }
        }
        // Recorded after the continuation is stored, so a test that waits on
        // the request count can emit straight away.
        state.withLock { $0.requests.append(request) }
        return stream
    }
}

private final class StubActions: AssistantActionsClientProtocol, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (confirmed: [UUID](), cancelled: [UUID]()))
    var confirmResult: Result<AssistantActionResolutionDTO, any Error> = .success(.init(status: .confirmed, message: "ok"))
    var cancelResult: Result<AssistantActionResolutionDTO, any Error> = .success(.init(status: .cancelled, message: "ok"))
    var confirmed: [UUID] { state.withLock { $0.confirmed } }
    var cancelled: [UUID] { state.withLock { $0.cancelled } }

    func confirm(_ id: UUID) async throws -> AssistantActionResolutionDTO {
        state.withLock { $0.confirmed.append(id) }
        return try confirmResult.get()
    }

    func cancel(_ id: UUID) async throws -> AssistantActionResolutionDTO {
        state.withLock { $0.cancelled.append(id) }
        return try cancelResult.get()
    }
}

@MainActor
private final class StubSpeech: SpeechSynthesizing {
    var isSpeaking = false
    var spoken: [String] = []
    var stopCount = 0

    func speak(_ text: String, onStart _: @escaping @MainActor () -> Void, onFinish _: @escaping @MainActor () -> Void) {
        spoken.append(text)
    }

    func stop() { stopCount += 1 }
}
