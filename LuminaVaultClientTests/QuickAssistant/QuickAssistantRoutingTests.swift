// LuminaVaultClient/LuminaVaultClientTests/QuickAssistant/QuickAssistantRoutingTests.swift
//
// Where an `openScreen` action goes, when it goes, and what a dismissed card
// does (nothing). The route is a pure mapping; the timing lives in the model,
// which acts when the turn ends rather than when the frame arrives, because
// closing the card cancels the stream.
@testable import LuminaVaultClient
import LuminaVaultShared
import os
import XCTest

@MainActor
final class QuickAssistantRoutingTests: XCTestCase {
    private typealias Route = QuickAssistantRoute

    // MARK: - Mapping

    func testTabScreensMapToTabs() {
        XCTAssertEqual(Route.resolve(.home, memoryID: nil), .tab(.home))
        XCTAssertEqual(Route.resolve(.spaces, memoryID: nil), .tab(.workspaces))
        XCTAssertEqual(Route.resolve(.ai, memoryID: nil), .tab(.think))
        XCTAssertEqual(Route.resolve(.brain, memoryID: nil), .tab(.brain))
        XCTAssertEqual(Route.resolve(.insights, memoryID: nil), .tab(.reflect))
    }

    func testBriefAndLearnedAreDeepLinks() {
        XCTAssertEqual(Route.resolve(.brief, memoryID: nil), .deepLink(.brief))
        XCTAssertEqual(Route.resolve(.learned, memoryID: nil), .deepLink(.learned))
    }

    func testMemoryWithIDIsDeepLink() {
        let id = UUID()
        XCTAssertEqual(Route.resolve(.memory, memoryID: id), .deepLink(.memory(id: id)))
    }

    func testMemoryWithoutIDIsNone() {
        XCTAssertEqual(Route.resolve(.memory, memoryID: nil), .none)
    }

    func testDataAccessRoutesToPermissions() {
        XCTAssertEqual(Route.resolve(.dataAccess, memoryID: nil), .dataAccess)
    }

    func testSettingsRoutesToSettings() {
        XCTAssertEqual(Route.resolve(.settings, memoryID: nil), .settings)
    }

    func testUnknownScreenIsNone() {
        XCTAssertEqual(Route.resolve(.unknown, memoryID: nil), .none)
    }

    func testEveryScreenResolvesWithoutTrapping() {
        for screen in AssistantScreenDTO.allCases {
            _ = Route.resolve(screen, memoryID: UUID())
            _ = Route.resolve(screen, memoryID: nil)
        }
    }

    // MARK: - Timing

    private final class Routed {
        var routes: [QuickAssistantRoute] = []
    }

    private func session(
        script: [QueryStreamEvent],
        actions: any AssistantActionsClientProtocol = QuickAssistantStubActions(),
        routed: Routed
    ) -> (QuickAssistantSession, QuickAssistantStubConversations) {
        let conversations = QuickAssistantStubConversations()
        conversations.script = script
        let session = QuickAssistantFixture.session(conversations: conversations, actions: actions)
        session.model.onOpenScreen = { routed.routes.append($0) }
        return (session, conversations)
    }

    private func finish(_ session: QuickAssistantSession) async {
        await session.model.send("open it", viaVoice: false, currentTab: "home", activeSpaceID: nil)
    }

    private func screen(_ screen: AssistantScreenDTO, memoryID: UUID? = nil) -> QueryStreamEvent {
        .assistantAction(AssistantActionDTO(
            id: UUID(), kind: .openScreen, summary: "Opening", screen: screen, memoryID: memoryID
        ))
    }

    private func confirm(_ id: UUID = UUID()) -> AssistantActionDTO {
        AssistantActionDTO(id: id, kind: .needsConfirm, summary: "Add to Calendar: Dentist", expiresAt: Date().addingTimeInterval(300))
    }

    func testOpenScreenRoutesWhenTheTurnEndsNotWhenTheFrameArrives() async {
        let routed = Routed()
        let (session, conversations) = session(script: [.token("Opening."), screen(.brain)], routed: routed)
        conversations.holdsStream = true
        let turn = Task { await finish(session) }
        for _ in 0 ..< 400 where session.model.pendingScreen == nil { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(session.model.pendingScreen, "the frame arrived")
        XCTAssertTrue(routed.routes.isEmpty, "the frame alone must not route")

        conversations.endHeldStream(with: [.done])
        await turn.value
        XCTAssertEqual(routed.routes, [.tab(.brain)])
    }

    func testOpenScreenRoutesOnceAfterDone() async {
        let routed = Routed()
        let (session, _) = session(script: [.token("Opening."), screen(.brain), .done], routed: routed)
        await finish(session)
        XCTAssertEqual(routed.routes, [.tab(.brain)])
        XCTAssertEqual(session.model.phase, .idle)
    }

    func testStreamFailureAfterOpenScreenDoesNotRoute() async {
        let routed = Routed()
        let (session, _) = session(script: [screen(.brain), .error("boom")], routed: routed)
        await finish(session)
        XCTAssertTrue(routed.routes.isEmpty)
        if case .failed = session.model.phase {} else { XCTFail("expected failed, got \(session.model.phase)") }
    }

    func testCutOffStreamAfterOpenScreenDoesNotRoute() async {
        let routed = Routed()
        let (session, _) = session(script: [.token("x"), screen(.brain)], routed: routed) // no `done`
        await finish(session)
        XCTAssertTrue(routed.routes.isEmpty)
        XCTAssertEqual(session.model.phase, .failed(QuickAssistantGate.cutOffMessage))
    }

    func testUnknownScreenRoutesNothing() async {
        let routed = Routed()
        let (session, _) = session(script: [screen(.unknown), .done], routed: routed)
        await finish(session)
        XCTAssertTrue(routed.routes.isEmpty)
    }

    func testMemoryWithoutIDRoutesNothing() async {
        let routed = Routed()
        let (session, _) = session(script: [screen(.memory), .done], routed: routed)
        await finish(session)
        XCTAssertTrue(routed.routes.isEmpty)
    }

    func testUnresolvedConfirmHoldsTheScreenAsARow() async {
        let routed = Routed()
        let ask = confirm()
        let (session, _) = session(script: [.assistantAction(ask), screen(.settings), .done], routed: routed)
        await finish(session)
        XCTAssertTrue(routed.routes.isEmpty, "closing would discard a card the user must answer")
        XCTAssertEqual(session.model.heldScreenRoute, .settings)
    }

    func testNoConfirmCardMeansTheScreenRoutesAtOnce() async {
        let routed = Routed()
        let (session, _) = session(script: [screen(.settings), .done], routed: routed)
        await finish(session)
        XCTAssertEqual(routed.routes, [.settings])
        XCTAssertNil(session.model.heldScreenRoute)
    }

    func testNewTurnClearsAHeldScreen() async {
        let routed = Routed()
        let (session, conversations) = session(
            script: [.assistantAction(confirm()), screen(.settings), .done], routed: routed
        )
        await finish(session)
        XCTAssertNotNil(session.model.heldScreenRoute)
        conversations.script = [.token("ok"), .done]
        await finish(session)
        XCTAssertNil(session.model.heldScreenRoute)
    }

    // MARK: - Dismissal

    func testClosingTheCardWithAnUnresolvedConfirmRunsNothing() async {
        let routed = Routed()
        let actions = RecordingActions()
        let (session, _) = session(
            script: [.assistantAction(confirm()), screen(.brain), .done], actions: actions, routed: routed
        )
        await finish(session)
        session.close() // what a tap on the dim does
        XCTAssertTrue(actions.confirmed.isEmpty)
        XCTAssertTrue(actions.cancelled.isEmpty)
        XCTAssertTrue(routed.routes.isEmpty)
    }
}

/// Counts calls and answers with a scripted result. Nothing here ever touches a network.
final class RecordingActions: AssistantActionsClientProtocol, @unchecked Sendable {
    // @unchecked: the lock guards every field.
    private struct State {
        var confirmed: [UUID] = []
        var cancelled: [UUID] = []
        var result: Result<AssistantActionResolutionDTO, any Error> = .success(.init(status: .confirmed, message: "Done."))
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    var confirmed: [UUID] { state.withLock { $0.confirmed } }
    var cancelled: [UUID] { state.withLock { $0.cancelled } }
    var result: Result<AssistantActionResolutionDTO, any Error> {
        get { state.withLock { $0.result } }
        set { state.withLock { $0.result = newValue } }
    }

    func confirm(_ id: UUID) async throws -> AssistantActionResolutionDTO {
        state.withLock { $0.confirmed.append(id) }
        return try result.get()
    }

    func cancel(_ id: UUID) async throws -> AssistantActionResolutionDTO {
        state.withLock { $0.cancelled.append(id) }
        return try result.get()
    }
}
