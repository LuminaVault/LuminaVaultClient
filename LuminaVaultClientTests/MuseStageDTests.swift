// LuminaVaultClient/LuminaVaultClientTests/MuseStageDTests.swift
//
// Muse Stage D — push routing, the agent-run Live Activity's state, and the
// "Watch this" intent.
//
// Every test is async: synchronous `@MainActor` tests have crashed this host
// ("pointer being freed was not allocated").

import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

// MARK: - Routing

@MainActor
final class MuseChatPushRoutingTests: XCTestCase {
    private let conversationID = UUID()

    /// The payload `ProactiveChatDelivery` sends, verbatim.
    private var proactivePayload: [AnyHashable: Any] {
        [
            "aps": ["category": "chat"],
            "category": "chat",
            "conversationID": conversationID.uuidString,
            "messageID": UUID().uuidString,
            "origin": "proactive",
            "sourceLabel": "daily-brief",
            "deepLink": "luminavault://chat/\(conversationID.uuidString)",
        ]
    }

    func testProactiveChatPushOpensItsConversation() async {
        let router = NotificationRouter()
        XCTAssertEqual(router.deepLink(from: proactivePayload), .conversation(id: conversationID))
    }

    func testChatPushWithOnlyADeepLinkStillOpensTheConversation() async {
        let router = NotificationRouter()
        let link = router.deepLink(from: [
            "category": "chat",
            "deepLink": "luminavault://chat/\(conversationID.uuidString)",
        ])
        XCTAssertEqual(link, .conversation(id: conversationID))
    }

    func testChatPushWithoutAThreadKeepsTheOldThinkBehaviour() async {
        let router = NotificationRouter()
        XCTAssertEqual(
            router.deepLink(from: ["category": "chat", "systemMessage": "hi"]),
            .think(systemMessage: "hi")
        )
    }

    func testChatURLParses() async {
        let url = URL(string: "luminavault://chat/\(conversationID.uuidString)")!
        XCTAssertEqual(NotificationRouter.deepLink(from: url), .conversation(id: conversationID))
    }

    func testOtherURLsAreNotChatLinks() async {
        for raw in [
            "luminavault://chat/not-a-uuid",
            "luminavault://chat",
            "luminavault://pair?id=1&code=2",
            "luminavault://oauth/google-gmail?status=ok",
            "https://app.luminavault.fyi/chat/\(conversationID.uuidString)",
            "luminavault://chat/\(conversationID.uuidString)/extra",
        ] {
            XCTAssertEqual(NotificationRouter.deepLink(from: URL(string: raw)!), .none, raw)
        }
    }

    /// A chat push arriving while the app is open shows its banner and waits
    /// for a tap; other categories keep routing on delivery as before.
    func testForegroundDeliveryDoesNotYankIntoAChat() async {
        XCTAssertFalse(NotificationRouter.routesOnForegroundDelivery(.conversation(id: conversationID)))
        XCTAssertFalse(NotificationRouter.routesOnForegroundDelivery(.none))
        XCTAssertTrue(NotificationRouter.routesOnForegroundDelivery(.hermesRun(runID: UUID())))
    }

    /// Warm start: the router is already wired, the tap routes straight in.
    func testWarmStartTapRoutesImmediately() async {
        let delegate = NotificationsAppDelegate()
        let router = NotificationRouter()
        delegate.router = router

        delegate.route(userInfo: proactivePayload)

        XCTAssertEqual(router.pendingDeepLink, .conversation(id: conversationID))
        XCTAssertNil(delegate.unroutedLink)
    }

    /// Cold start: iOS hands over the tap before the SwiftUI root has set the
    /// router. The link is parked and delivered once it is.
    func testColdStartTapIsParkedUntilTheRouterExists() async {
        let delegate = NotificationsAppDelegate()

        delegate.route(userInfo: proactivePayload)
        XCTAssertEqual(delegate.unroutedLink, .conversation(id: conversationID))

        let router = NotificationRouter()
        delegate.router = router

        XCTAssertEqual(router.pendingDeepLink, .conversation(id: conversationID))
        XCTAssertNil(delegate.unroutedLink)
    }

    func testChatCategoryIsRegistered() async {
        XCTAssertTrue(HermesRunNotifications.all.contains { $0.identifier == "chat" })
    }
}

// MARK: - Live Activity state

@MainActor
final class AgentRunActivityStateTests: XCTestCase {
    func testToolStateCarriesTheHeaderCopyAndTheLabel() async {
        let state = AgentRunActivityContent.running(.tool(label: "searching the web"), title: "Plan Lisbon")
        XCTAssertEqual(state.status, "is searching the web")
        XCTAssertEqual(state.toolLabel, "searching the web")
        XCTAssertEqual(state.stage, .working)
        XCTAssertEqual(state.title, "Plan Lisbon")
    }

    func testDelegatedWaitUsesTheYouCanLeaveLine() async {
        let state = AgentRunActivityContent.running(.delegated, title: nil)
        XCTAssertEqual(state.status, MuseChatState.delegated.status)
        XCTAssertEqual(state.status, "is still working — you can leave")
        XCTAssertNil(state.toolLabel)
        XCTAssertEqual(state.title, AgentRunActivityContent.fallbackTitle)
    }

    func testApprovalIsTheWaitingStage() async {
        let state = AgentRunActivityContent.running(.awaitingApproval, title: "x")
        XCTAssertEqual(state.stage, .waiting)
        XCTAssertEqual(state.status, "is waiting for you")
    }

    func testFinalStates() async {
        XCTAssertEqual(AgentRunActivityContent.finished(.finished, title: "x").stage, .done)
        XCTAssertEqual(AgentRunActivityContent.finished(.finished, title: "x").status, "has your answer")
        let failed = AgentRunActivityContent.finished(.failed("boom"), title: "x")
        XCTAssertEqual(failed.stage, .failed)
        XCTAssertEqual(failed.status, "hit a snag")
        XCTAssertEqual(AgentRunActivityContent.finished(.following, title: "x").status, "stopped")
    }

    func testTitleIsOneShortLine() async {
        XCTAssertEqual(AgentRunActivityContent.clampTitle("  plan   my\ntrip  "), "plan my")
        let long = String(repeating: "word ", count: 30)
        let clamped = AgentRunActivityContent.clampTitle(long)
        XCTAssertLessThanOrEqual(clamped.count, AgentRunActivityContent.titleMaxLength)
        XCTAssertTrue(clamped.hasSuffix("…"))
        XCTAssertEqual(AgentRunActivityContent.clampTitle("   "), AgentRunActivityContent.fallbackTitle)
    }

    // MARK: Throttle

    private func state(_ status: String) -> AgentRunAttributes.ContentState {
        .init(title: "t", status: status, toolLabel: nil, stage: .working)
    }

    func testThrottleSendsFirstThenDefersThenCoalesces() async {
        var throttle = LiveActivityThrottle(minimumInterval: 2)
        let t0 = Date(timeIntervalSince1970: 1000)

        XCTAssertEqual(throttle.offer(state("a"), at: t0), .send)
        XCTAssertEqual(throttle.offer(state("a"), at: t0.addingTimeInterval(0.1)), .drop)
        XCTAssertEqual(throttle.offer(state("b"), at: t0.addingTimeInterval(0.5)), .later(1.5))
        // A newer state replaces the pending one; the timer already running
        // will pick it up.
        _ = throttle.offer(state("c"), at: t0.addingTimeInterval(1))
        XCTAssertEqual(throttle.flush(at: t0.addingTimeInterval(2)), state("c"))
        XCTAssertNil(throttle.flush(at: t0.addingTimeInterval(2.1)))
        XCTAssertEqual(throttle.offer(state("d"), at: t0.addingTimeInterval(4.5)), .send)
    }

    func testThrottleDropsAPendingStateThatReturnedToWhatIsShowing() async {
        var throttle = LiveActivityThrottle(minimumInterval: 2)
        let t0 = Date(timeIntervalSince1970: 1000)
        _ = throttle.offer(state("a"), at: t0)
        _ = throttle.offer(state("b"), at: t0.addingTimeInterval(0.5))
        XCTAssertEqual(throttle.offer(state("a"), at: t0.addingTimeInterval(1)), .drop)
        XCTAssertNil(throttle.flush(at: t0.addingTimeInterval(2)))
    }
}

// MARK: - Follower → Live Activity

@MainActor
final class ChatRunFollowerLiveActivityTests: XCTestCase {
    private func makeFollower(
        _ client: StubHermesRunsClient,
        recorder: RecordingLiveActivity,
        conversationID: UUID? = UUID()
    ) -> ChatRunFollower {
        ChatRunFollower(
            client: client,
            runID: UUID(),
            conversationID: conversationID,
            title: "What's the weather this week?",
            liveActivity: recorder,
            reconnectDelays: [0, 0]
        )
    }

    func testStartsOnFollowUpdatesOnTrailAndEndsDone() async {
        let client = StubHermesRunsClient()
        client.connections = [.events([
            .stub(seq: 1, event: "run.started"),
            .stub(seq: 2, event: "tool.started", fields: ["tool": .string("web_search")]),
            .stub(seq: 3, event: "tool.completed", fields: ["tool": .string("web_search")]),
            .stub(seq: 4, event: "message.delta", fields: ["delta": .string("Sunny")]),
            .stub(seq: 5, event: "run.completed"),
        ])]
        client.getQueue = [.stub(status: .completed)]
        let recorder = RecordingLiveActivity()
        let conversationID = UUID()
        let sut = makeFollower(client, recorder: recorder, conversationID: conversationID)

        await sut.follow()

        XCTAssertEqual(recorder.started.count, 1)
        XCTAssertEqual(recorder.started.first?.conversationID, conversationID)
        XCTAssertEqual(recorder.started.first?.state.status, "is still working — you can leave")
        XCTAssertEqual(recorder.started.first?.state.title, "What's the weather this week?")
        XCTAssertTrue(recorder.updates.contains { $0.toolLabel == "searching the web" && $0.status == "is searching the web" })
        XCTAssertEqual(recorder.updates.last?.status, "is writing")
        XCTAssertEqual(recorder.ends.count, 1)
        XCTAssertEqual(recorder.ends.first?.state.stage, .done)
        XCTAssertEqual(recorder.ends.first?.immediately, false)
    }

    func testRunFailedEventEndsAsASnag() async {
        let client = StubHermesRunsClient()
        client.connections = [.events([
            .stub(seq: 1, event: "run.started"),
            .stub(seq: 2, event: "run.failed"),
        ])]
        client.getQueue = [.stub(status: .failed)]
        let recorder = RecordingLiveActivity()
        let sut = makeFollower(client, recorder: recorder)

        await sut.follow()

        XCTAssertEqual(recorder.ends.first?.state.stage, .failed)
        XCTAssertEqual(recorder.ends.first?.state.status, "hit a snag")
    }

    func testApprovalRequestShowsTheWaitingStage() async {
        let client = StubHermesRunsClient()
        let recorder = RecordingLiveActivity()
        let sut = makeFollower(client, recorder: recorder)

        sut.apply(.stub(seq: 1, event: "approval.request", fields: ["tool": .string("shell")]))

        XCTAssertEqual(recorder.updates.last?.stage, .waiting)
    }

    func testCancelledFollowEndsImmediately() async {
        let client = StubHermesRunsClient()
        // A feed that never ends on its own: the follower keeps reconnecting.
        client.connections = []
        client.getResult = .success(.stub(status: .running))
        let recorder = RecordingLiveActivity()
        let sut = ChatRunFollower(
            client: client,
            runID: UUID(),
            title: "x",
            liveActivity: recorder,
            reconnectDelays: [30]
        )
        let task = Task { await sut.follow() }
        // Let it start and park in the backoff sleep.
        for _ in 0 ..< 50 where recorder.started.isEmpty { await Task.yield() }
        task.cancel()
        await task.value

        XCTAssertEqual(recorder.ends.first?.immediately, true)
        XCTAssertEqual(recorder.ends.first?.state.status, "stopped")
    }
}

@MainActor
final class RecordingLiveActivity: AgentRunLiveActivityControlling {
    struct Start {
        let runID: UUID
        let conversationID: UUID?
        let state: AgentRunAttributes.ContentState
    }

    private(set) var started: [Start] = []
    private(set) var updates: [AgentRunAttributes.ContentState] = []
    private(set) var ends: [(state: AgentRunAttributes.ContentState, immediately: Bool)] = []

    func start(runID: UUID, conversationID: UUID?, state: AgentRunAttributes.ContentState) {
        started.append(Start(runID: runID, conversationID: conversationID, state: state))
    }

    func update(_ state: AgentRunAttributes.ContentState) {
        if updates.last != state { updates.append(state) }
    }

    func end(_ state: AgentRunAttributes.ContentState, immediately: Bool) {
        ends.append((state, immediately))
    }
}

// MARK: - Watch this

final class WatchThisIntentFlowTests: XCTestCase {
    private let weatherJob = JobProposalDTO(
        isJob: true,
        title: "Weather watch",
        cron: "0 7 * * *",
        scheduleHuman: "Every day at 7:00",
        domain: "life",
        spec: "Check the weather each morning; alert when there are 5 consecutive dry days."
    )

    func testAJobIsCreatedAndTheDialogSaysTheSchedule() async {
        let jobs = ScriptedJobsClient(detect: .success(weatherJob))
        let outcome = await WatchThisFlow(client: jobs).run("  check the weather every morning  ")

        let detected = await jobs.detectedTexts
        let created = await jobs.created
        XCTAssertEqual(detected, ["check the weather every morning"])
        XCTAssertEqual(created.map(\.cron), ["0 7 * * *"])
        XCTAssertEqual(created.first?.title, "Weather watch")

        guard case let .created(title, _, schedule) = outcome else {
            return XCTFail("expected created, got \(outcome)")
        }
        XCTAssertEqual(title, "Weather watch")
        XCTAssertEqual(schedule, "Every day at 7:00")
        let dialog = WatchThisFlow.dialog(for: outcome)
        XCTAssertTrue(dialog.hasPrefix("Got it — I'll watch weather watch"), dialog)
        XCTAssertTrue(dialog.contains("Every day at 7:00"), dialog)
    }

    func testNotAJobCreatesNothingAndSaysSo() async {
        let jobs = ScriptedJobsClient(detect: .success(JobProposalDTO(isJob: false)))
        let outcome = await WatchThisFlow(client: jobs).run("what's 2+2")

        XCTAssertEqual(outcome, .notAJob)
        let created = await jobs.created
        XCTAssertTrue(created.isEmpty)
        XCTAssertTrue(WatchThisFlow.dialog(for: outcome).contains("doesn't sound like something to watch"))
    }

    func testAJobWithoutAScheduleIsNotCreated() async {
        let jobs = ScriptedJobsClient(detect: .success(JobProposalDTO(isJob: true, title: "x", cron: nil, spec: "y")))
        let outcome = await WatchThisFlow(client: jobs).run("watch x")
        XCTAssertEqual(outcome, .notAJob)
        let created = await jobs.created
        XCTAssertTrue(created.isEmpty)
    }

    func testEmptyTextNeverCallsTheServer() async {
        let jobs = ScriptedJobsClient(detect: .success(weatherJob))
        let outcome = await WatchThisFlow(client: jobs).run("   ")
        XCTAssertEqual(outcome, .empty)
        let detected = await jobs.detectedTexts
        XCTAssertTrue(detected.isEmpty)
    }

    func testSignedOutAndFailuresAreSaidPlainly() async {
        let signedOut = await WatchThisFlow(client: ScriptedJobsClient(detect: .failure(APIError.unauthorized))).run("x")
        XCTAssertEqual(signedOut, .signedOut)

        let createFails = ScriptedJobsClient(detect: .success(weatherJob), createFails: true)
        let failed = await WatchThisFlow(client: createFails).run("x")
        XCTAssertEqual(failed, .failed)
        XCTAssertTrue(WatchThisFlow.dialog(for: failed).contains("couldn't set that up"))
    }
}

private actor ScriptedJobsClient: JobsClientProtocol {
    private let detectResult: Result<JobProposalDTO, any Error>
    private let createFails: Bool
    private(set) var detectedTexts: [String] = []
    private(set) var created: [JobCreateRequest] = []

    init(detect: Result<JobProposalDTO, any Error>, createFails: Bool = false) {
        detectResult = detect
        self.createFails = createFails
    }

    func detect(text: String) async throws -> JobProposalDTO {
        detectedTexts.append(text)
        return try detectResult.get()
    }

    func create(_ request: JobCreateRequest) async throws -> LuminaVaultShared.SkillDTO {
        if createFails { throw APIError.networkFailure(URLError(.notConnectedToInternet)) }
        created.append(request)
        return SkillDTO(
            id: "job-weather-watch", source: .vault, name: "job-weather-watch", title: request.title,
            descriptionText: "", capability: .medium, enabled: true, bodyExcerpt: ""
        )
    }
}
