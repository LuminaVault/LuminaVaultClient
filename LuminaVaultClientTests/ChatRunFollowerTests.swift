// LuminaVaultClient/LuminaVaultClientTests/ChatRunFollowerTests.swift
//
// The follower behind an escalated chat turn.
//
// The behaviours worth pinning are the ones a user would notice breaking:
// token deltas must not each become a trail row, a reconnect must resume from
// the cursor rather than replaying the run, and a feed that never sends a
// terminal event must eventually give up instead of spinning forever.

import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

@MainActor
final class ChatRunFollowerTests: XCTestCase {
    private var client: StubHermesRunsClient!

    /// Zeroed so the reconnect budget is walked instantly.
    private static let noDelays: [Double] = [0, 0]

    override func setUp() async throws {
        try await super.setUp()
        client = StubHermesRunsClient()
        client.run = .stub(status: .running)
    }

    private func makeFollower(sessionID: String? = nil) -> ChatRunFollower {
        ChatRunFollower(
            client: client,
            runID: UUID(),
            sessionID: sessionID,
            reconnectDelays: Self.noDelays
        )
    }

    func testDeltasFoldIntoOneAnswerInsteadOfOneRowEach() async {
        client.connections = [
            .events([
                .stub(seq: 1, event: "run.started"),
                .stub(seq: 2, event: "message.delta", fields: ["delta": .string("Hel")]),
                .stub(seq: 3, event: "message.delta", fields: ["delta": .string("lo")]),
                .stub(seq: 4, event: "run.completed"),
            ]),
        ]
        client.getQueue = [.stub(status: .completed)]

        let sut = makeFollower()
        await sut.follow()

        XCTAssertEqual(sut.answer, "Hello")
        XCTAssertEqual(sut.trail.map(\.title), ["Run started", "Run finished"])
        XCTAssertTrue(sut.isFinished)
    }

    func testToolEventsBecomeTrailRows() async {
        client.connections = [
            .events([
                .stub(seq: 1, event: "tool.started", fields: ["tool": .string("shell")]),
                .stub(seq: 2, event: "tool.completed", fields: ["tool": .string("shell")]),
                .stub(seq: 3, event: "run.completed"),
            ]),
        ]
        client.getQueue = [.stub(status: .completed)]

        let sut = makeFollower()
        await sut.follow()

        XCTAssertEqual(sut.trail.map(\.title), ["Running shell", "shell finished", "Run finished"])
    }

    /// Replay-then-live re-sends what we already hold after a reconnect.
    /// Without the watermark every reconnect would duplicate rows.
    func testEventsAtOrBelowTheCursorAreIgnored() async {
        client.connections = [
            .events([
                .stub(seq: 5, event: "tool.started", fields: ["tool": .string("shell")]),
                .stub(seq: 5, event: "tool.started", fields: ["tool": .string("shell")]),
                .stub(seq: 3, event: "tool.started", fields: ["tool": .string("stale")]),
                .stub(seq: 6, event: "run.completed"),
            ]),
        ]
        client.getQueue = [.stub(status: .completed)]

        let sut = makeFollower()
        await sut.follow()

        XCTAssertEqual(sut.trail.count, 2)
        XCTAssertEqual(sut.cursor, 6)
    }

    func testReconnectResumesFromTheCursor() async {
        client.connections = [
            .events([.stub(seq: 4, event: "tool.started", fields: ["tool": .string("shell")])]),
            .events([.stub(seq: 9, event: "run.completed")]),
        ]
        client.getQueue = [.stub(status: .running), .stub(status: .completed)]

        let sut = makeFollower()
        await sut.follow()

        XCTAssertEqual(client.requestedCursors, [0, 4])
        XCTAssertTrue(sut.isFinished)
    }

    func testFollowStartsFromASuppliedCursor() async {
        client.connections = [.events([.stub(seq: 12, event: "run.completed")])]
        client.getQueue = [.stub(status: .completed)]

        let sut = makeFollower()
        await sut.follow(after: 11)

        XCTAssertEqual(client.requestedCursors.first, 11)
    }

    /// A feed that closes cleanly without ever sending a terminal event would
    /// otherwise spin forever: each pass replays the same frames, all at or
    /// below the cursor, and nothing advances.
    func testGivesUpWhenTheFeedNeverTerminates() async {
        client.connections = [.events([])]
        client.run = .stub(status: .running)

        let sut = makeFollower()
        await sut.follow()

        guard case .failed = sut.phase else {
            return XCTFail("expected the follower to give up, got \(sut.phase)")
        }
    }

    func testTerminalRunStatusEndsTheFollowEvenWithoutATerminalEvent() async {
        // The feed can end before the terminal event reaches us; the run
        // itself is the authority on whether anything is left to follow.
        client.connections = [.events([.stub(seq: 1, event: "tool.started")])]
        client.getQueue = [.stub(status: .completed, summary: "all done")]

        let sut = makeFollower()
        await sut.follow()

        XCTAssertTrue(sut.isFinished)
        XCTAssertEqual(sut.answer, "all done")
    }

    func testApprovalIsHeldUntilAnswered() async {
        let sut = makeFollower()
        sut.apply(.stub(
            seq: 1,
            event: "approval.request",
            fields: ["command": .string("rm -rf build")]
        ))
        XCTAssertEqual(sut.pendingApproval?.detail, "rm -rf build")

        sut.apply(.stub(seq: 2, event: "approval.responded", fields: ["choice": .string("once")]))
        XCTAssertNil(sut.pendingApproval)
    }

    func testRespondSendsTheChoiceAndClearsThePrompt() async {
        let sut = makeFollower()
        sut.apply(.stub(seq: 1, event: "approval.request", fields: ["command": .string("ls")]))

        await sut.respond(.session)

        XCTAssertEqual(client.approvedChoices, [.session])
        XCTAssertNil(sut.pendingApproval)
    }

    /// The pointer carries the session, and it must survive the follow so the
    /// artifact strip can scope itself to this turn.
    func testSessionIDFromThePointerSurvives() async {
        client.connections = [.events([.stub(seq: 1, event: "run.completed")])]
        client.getQueue = [.stub(status: .completed)]

        let sut = makeFollower(sessionID: "sess-abc")
        await sut.follow()

        XCTAssertEqual(sut.sessionID, "sess-abc")
    }

    func testTerminalWatcherEventEndsTheRun() async {
        // The server synthesises `watcher.*` when Hermes never sent a terminal
        // state. Ignoring it would leave the follower streaming forever.
        let sut = makeFollower()
        sut.apply(.stub(seq: 1, event: "watcher.timeout"))
        XCTAssertTrue(sut.isFinished)
    }

    // MARK: - Muse Stage B: tool labels and first token

    func testToolStartedCarriesAHeaderLabelAndCompletionClearsIt() async {
        let sut = makeFollower()
        sut.apply(.stub(seq: 1, event: "tool.started", fields: ["tool": .string("web_search")]))
        XCTAssertEqual(sut.trail.last?.toolLabel, "searching the web")

        sut.apply(.stub(seq: 2, event: "tool.completed", fields: ["tool": .string("web_search")]))
        XCTAssertNil(sut.trail.last?.toolLabel)
    }

    func testProgressWithoutAToolNameKeepsTheRunningLabel() async {
        let sut = makeFollower()
        sut.apply(.stub(seq: 1, event: "tool.started", fields: ["tool": .string("terminal")]))
        sut.apply(.stub(seq: 2, event: "tool.progress", fields: ["text": .string("npm install")]))
        XCTAssertEqual(sut.trail.last?.toolLabel, "running code")
    }

    func testExplicitLabelOnTheWirePassesThrough() async {
        let sut = makeFollower()
        sut.apply(.stub(seq: 1, event: "tool.started", fields: [
            "tool": .string("web_search"),
            "label": .string("checking flight prices"),
        ]))
        XCTAssertEqual(sut.trail.last?.toolLabel, "checking flight prices")
    }

    func testFailedToolCarriesNoLabel() async {
        let sut = makeFollower()
        sut.apply(.stub(seq: 1, event: "tool.started", fields: ["tool": .string("shell")]))
        sut.apply(.stub(seq: 2, event: "tool.failed", fields: ["tool": .string("shell")]))
        XCTAssertNil(sut.trail.last?.toolLabel)
    }

    func testHasAnswerFlipsOnTheFirstDelta() async {
        let sut = makeFollower()
        XCTAssertFalse(sut.hasAnswer)
        sut.apply(.stub(seq: 1, event: "message.delta", fields: ["delta": .string("")]))
        XCTAssertFalse(sut.hasAnswer, "an empty delta is not a token")
        sut.apply(.stub(seq: 2, event: "message.delta", fields: ["delta": .string("Hi")]))
        XCTAssertTrue(sut.hasAnswer)
    }
}
