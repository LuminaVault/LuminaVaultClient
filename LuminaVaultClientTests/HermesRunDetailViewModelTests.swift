// LuminaVaultClient/LuminaVaultClientTests/HermesRunDetailViewModelTests.swift
//
// Hermes Companion Phase 1 — the live run screen's state machine.
//
// The behaviours worth pinning down are the ones a user would notice
// breaking: token deltas must not each become a trail row, a reconnect must
// resume from the cursor instead of replaying the run, and the approval
// buttons must be exactly the ones the server offered.

import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

@MainActor
final class HermesRunDetailViewModelTests: XCTestCase {
    private var client: StubHermesRunsClient!
    private var sut: HermesRunDetailViewModel!

    /// Zeroed so the reconnect budget is walked instantly.
    private static let noDelays: [Double] = [0, 0, 0, 0]

    override func setUp() async throws {
        try await super.setUp()
        client = StubHermesRunsClient()
        client.run = .stub(status: .running)
        sut = HermesRunDetailViewModel(
            client: client,
            run: .stub(status: .running),
            reconnectDelays: Self.noDelays
        )
    }

    // MARK: - Feed

    func testDeltasFoldIntoOneAnswerInsteadOfOneRowEach() async {
        client.connections = [
            .events([
                .stub(seq: 1, event: "run.started"),
                .stub(seq: 2, event: "message.delta", fields: ["delta": .string("Hello")]),
                .stub(seq: 3, event: "message.delta", fields: ["delta": .string(", world")]),
                .stub(seq: 4, event: "run.completed"),
            ]),
        ]
        client.getQueue = [.stub(status: .completed)]

        await sut.follow()

        XCTAssertEqual(sut.liveMessage, "Hello, world")
        // run.started + run.completed — the two deltas are not rows.
        XCTAssertEqual(sut.trail.map(\.title), ["Run started", "Run finished"])
    }

    func testToolEventsBecomeReadableTrailRows() async {
        client.connections = [
            .events([
                .stub(seq: 1, event: "tool.started", fields: ["tool": .string("bash"), "preview": .string("ls -la")]),
                .stub(seq: 2, event: "tool.completed", fields: ["tool": .string("bash"), "duration": .number(1.5)]),
                .stub(seq: 3, event: "tool.failed", fields: ["tool": .string("http"), "error": .string("timeout")]),
                .stub(seq: 4, event: "run.completed"),
            ]),
        ]
        client.getQueue = [.stub(status: .completed)]

        await sut.follow()

        XCTAssertEqual(
            sut.trail.map(\.title),
            ["Running bash", "bash finished", "http failed", "Run finished"]
        )
        XCTAssertEqual(sut.trail[0].detail, "ls -la")
        XCTAssertEqual(sut.trail[1].detail, "1.5s")
        XCTAssertEqual(sut.trail[2].kind, .failure)
    }

    func testUnknownEventsStillAppearNamedRatherThanVanishing() async {
        client.connections = [
            .events([
                .stub(seq: 1, event: "hermes.something.new"),
                .stub(seq: 2, event: "run.completed"),
            ]),
        ]
        client.getQueue = [.stub(status: .completed)]

        await sut.follow()

        XCTAssertEqual(sut.trail.first?.title, "hermes.something.new")
    }

    func testCursorAdvancesAndIgnoresReplayedEvents() async {
        client.connections = [
            .events([
                .stub(seq: 5, event: "run.started"),
                // A duplicate the server replayed; must not double the trail.
                .stub(seq: 5, event: "run.started"),
                .stub(seq: 6, event: "run.completed"),
            ]),
        ]
        client.getQueue = [.stub(status: .completed)]

        await sut.follow()

        XCTAssertEqual(sut.cursor, 6)
        XCTAssertEqual(sut.trail.count, 2)
    }

    /// The behaviour the whole `?after=` design exists for: a dropped feed
    /// must reconnect from what the screen already holds, not from zero.
    func testReconnectResumesFromTheCursorRatherThanReplaying() async {
        client.connections = [
            .events([.stub(seq: 1, event: "run.started"), .stub(seq: 2, event: "tool.started")]),
            .failure(APIError.networkFailure(URLError(.networkConnectionLost))),
            .events([.stub(seq: 3, event: "run.completed")]),
        ]
        // Still running across both refreshes, terminal only at the end.
        client.getQueue = [
            .stub(status: .running),
            .stub(status: .running),
            .stub(status: .completed),
        ]

        await sut.follow()

        XCTAssertEqual(client.requestedCursors, [0, 2, 2])
        XCTAssertEqual(sut.cursor, 3)
    }

    func testFeedStopsRetryingWhenTheFailureCannotSucceed() async {
        client.connections = [
            .failure(APIError.httpError(statusCode: 501, data: Self.errorBody("hermes_runs_unsupported"))),
        ]

        await sut.follow()

        XCTAssertEqual(client.requestedCursors, [0])
        XCTAssertEqual(sut.actionError, .unsupported)
    }

    /// A feed that keeps closing empty while the run claims to be active is a
    /// broken connection, and the screen should say so instead of showing a
    /// "Live" indicator forever.
    func testEmptyReconnectsGiveUpWithinTheBudget() async {
        await sut.follow()

        XCTAssertEqual(client.requestedCursors.count, Self.noDelays.count + 1)
        XCTAssertEqual(sut.actionError, .upstream)
        XCTAssertFalse(sut.isFollowing)
    }

    // MARK: - Approval

    func testApprovalRequestRefreshesTheRunSoTheOfferedChoicesAppear() async {
        client.connections = [
            .events([.stub(seq: 1, event: "approval.request", fields: ["command": .string("rm -rf build")])]),
        ]
        client.getQueue = [
            .stub(
                status: .waitingForApproval,
                approval: HermesRunPendingApprovalDTO(
                    command: "rm -rf build",
                    choices: [.once, .deny],
                    requestedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            ),
        ]

        await sut.follow()

        // Exactly what the server offered — `session` and `always` are not
        // invented locally.
        XCTAssertEqual(sut.pendingApproval?.choices, [.once, .deny])
        XCTAssertEqual(sut.pendingApproval?.command, "rm -rf build")
        XCTAssertEqual(sut.trail.first?.kind, .approval)
    }

    func testPendingApprovalIsHiddenOnceTheRunIsNoLongerWaiting() {
        sut = HermesRunDetailViewModel(
            client: client,
            run: .stub(
                status: .running,
                approval: HermesRunPendingApprovalDTO(
                    command: "ls",
                    choices: [.once],
                    requestedAt: Date()
                )
            )
        )

        XCTAssertNil(sut.pendingApproval)
    }

    func testApprovePostsTheChoiceAndAdoptsTheReturnedRun() async {
        sut = HermesRunDetailViewModel(client: client, run: .stub(status: .waitingForApproval))
        client.approveResult = .success(.stub(status: .running))

        await sut.approve(.session)

        XCTAssertEqual(client.approvedChoices, [.session])
        XCTAssertEqual(sut.status, .running)
        XCTAssertNil(sut.actionError)
    }

    /// The race that actually happens: the user answered from the lock screen
    /// a second earlier, so the screen is holding a prompt the server has
    /// already retired.
    func testApproveConflictSurfacesAndResyncs() async {
        sut = HermesRunDetailViewModel(
            client: client,
            run: .stub(
                status: .waitingForApproval,
                approval: HermesRunPendingApprovalDTO(command: "ls", choices: [.once], requestedAt: Date())
            )
        )
        client.approveResult = .failure(
            APIError.httpError(statusCode: 409, data: Self.errorBody("hermes_approval_not_pending"))
        )
        client.getQueue = [.stub(status: .running)]

        await sut.approve(.once)

        XCTAssertEqual(sut.actionError, .approvalNotPending)
        XCTAssertEqual(sut.status, .running)
        XCTAssertNil(sut.pendingApproval)
    }

    // MARK: - Stop

    func testStopIsOfferedOnlyWhileTheRunCanStillBeStopped() {
        sut = HermesRunDetailViewModel(client: client, run: .stub(status: .running))
        XCTAssertTrue(sut.canStop)

        sut = HermesRunDetailViewModel(client: client, run: .stub(status: .completed))
        XCTAssertFalse(sut.canStop)
    }

    func testStopSendsAndKeepsTheScreenUsableWhenHermesAnswersStopping() async {
        sut = HermesRunDetailViewModel(client: client, run: .stub(status: .running))
        // Hermes answers "stopping": the DTO can still read running, and the
        // terminal state lands on the feed.
        client.stopResult = .success(.stub(status: .running))

        await sut.stop()

        XCTAssertEqual(client.stopCount, 1)
        XCTAssertFalse(sut.isStopping)
        XCTAssertNil(sut.actionError)
    }

    // MARK: - Load

    func testColdLoadFailureShowsTheFailureState() async {
        sut = HermesRunDetailViewModel(client: client, runID: Self.runID)
        client.getResult = .failure(
            APIError.httpError(statusCode: 501, data: Self.errorBody("hermes_runs_unsupported"))
        )

        await sut.load()

        XCTAssertEqual(sut.state, .failed(.unsupported))
    }

    /// A failed refresh must not blank a screen that already has content.
    func testRefreshFailureKeepsExistingContent() async {
        sut = HermesRunDetailViewModel(client: client, run: .stub(status: .running))
        client.getResult = .failure(APIError.networkFailure(URLError(.notConnectedToInternet)))

        await sut.load()

        XCTAssertEqual(sut.state, .loaded)
        XCTAssertEqual(sut.actionError, .offline)
        XCTAssertNotNil(sut.run)
    }

    func testTerminalRunPrefersTheServerSummaryOverPartialStreamedText() async {
        client.connections = [
            .events([.stub(seq: 1, event: "message.delta", fields: ["delta": .string("partia")])]),
        ]
        client.getQueue = [.stub(status: .completed, summary: "partial answer, completed")]

        await sut.follow()

        XCTAssertEqual(sut.liveMessage, "partial answer, completed")
    }

    private static let runID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private static func errorBody(_ code: String) -> Data {
        Data(#"{"error":{"message":"\#(code)"}}"#.utf8)
    }
}

// MARK: - Stubs

extension HermesRunDTO {
    static func stub(
        status: HermesRunStatus,
        approval: HermesRunPendingApprovalDTO? = nil,
        summary: String? = nil,
        prompt: String = "tidy the vault",
        lastEvent: String? = nil,
        lastSeq: Int = 0,
        id: UUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> HermesRunDTO {
        HermesRunDTO(
            id: id,
            hermesRunID: "run_stub",
            status: status,
            prompt: prompt,
            startedAt: startedAt,
            lastEvent: lastEvent,
            lastSeq: lastSeq,
            pendingApproval: approval,
            summary: summary
        )
    }
}

extension HermesRunEventDTO {
    static func stub(
        seq: Int,
        event: String,
        fields: [String: AnyJSONValue] = [:]
    ) -> HermesRunEventDTO {
        HermesRunEventDTO(
            runID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            seq: seq,
            event: event,
            payload: .object(fields),
            at: Date(timeIntervalSince1970: 1_700_000_000 + Double(seq))
        )
    }
}

/// Scripted `HermesRunsClientProtocol`. `connections` is consumed one entry
/// per `events(_:after:)` call, so a test can script "feed drops, then
/// reconnects" and assert the cursor each attempt carried. `getQueue` models
/// a run that moves on between refreshes; once drained, the last value keeps
/// being returned.
@MainActor
final class StubHermesRunsClient: HermesRunsClientProtocol {
    enum Connection {
        case events([HermesRunEventDTO])
        case failure(any Error)
    }

    var run: HermesRunDTO = .stub(status: .running)
    var getQueue: [HermesRunDTO] = []
    /// Overrides `getQueue` / `run` entirely — for failure paths.
    var getResult: Result<HermesRunDTO, any Error>?
    var approveResult: Result<HermesRunDTO, any Error>?
    var stopResult: Result<HermesRunDTO, any Error>?
    var startResult: Result<HermesRunDTO, any Error>?
    var listResult: Result<[HermesRunDTO], any Error>?

    var connections: [Connection] = []
    private(set) var requestedCursors: [Int] = []
    private(set) var approvedChoices: [HermesApprovalChoice] = []
    private(set) var stopCount = 0
    private(set) var startedRequests: [HermesRunStartRequest] = []
    private(set) var listLimits: [Int?] = []

    nonisolated func start(_ request: HermesRunStartRequest) async throws -> HermesRunDTO {
        try await MainActor.run {
            startedRequests.append(request)
            return try (startResult ?? .success(run)).get()
        }
    }

    nonisolated func list(limit: Int?) async throws -> [HermesRunDTO] {
        try await MainActor.run {
            listLimits.append(limit)
            return try (listResult ?? .success([run])).get()
        }
    }

    nonisolated func get(_: UUID) async throws -> HermesRunDTO {
        try await MainActor.run {
            if let getResult { return try getResult.get() }
            if !getQueue.isEmpty { run = getQueue.removeFirst() }
            return run
        }
    }

    nonisolated func approve(_: UUID, choice: HermesApprovalChoice) async throws -> HermesRunDTO {
        try await MainActor.run {
            approvedChoices.append(choice)
            let result = try (approveResult ?? .success(run)).get()
            run = result
            return result
        }
    }

    nonisolated func stop(_: UUID) async throws -> HermesRunDTO {
        try await MainActor.run {
            stopCount += 1
            let result = try (stopResult ?? .success(run)).get()
            run = result
            return result
        }
    }

    nonisolated func events(_: UUID, after: Int) -> AsyncThrowingStream<HermesRunEventDTO, any Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                requestedCursors.append(after)
                guard !connections.isEmpty else {
                    continuation.finish()
                    return
                }
                switch connections.removeFirst() {
                case .events(let events):
                    for event in events where event.seq > after {
                        continuation.yield(event)
                    }
                    continuation.finish()
                case .failure(let error):
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
