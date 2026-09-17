// LuminaVaultClient/LuminaVaultClientTests/GuidedStartCoordinatorTests.swift
//
// Guided start — the phase machine, the polling schedule, and the
// visibility rule, all driven with no AppState and no network.
//
// Every wait goes through the injected `sleep` closure, which advances a
// fake clock instead of sleeping, so the 5-minute timeout case runs in
// microseconds and the poll schedule is assertable as a list of Durations.

import XCTest
@testable import LuminaVaultClient
import LuminaVaultShared

@MainActor
final class GuidedStartCoordinatorTests: XCTestCase {

    // MARK: - Fakes

    /// Hands back a scripted sequence of snapshots, repeating the last one
    /// forever so a polling loop can keep asking without running dry.
    final class ScriptedOnboardingClient: OnboardingClientProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [OnboardingStateDTO]
        private var cursor = 0
        private var _getCount = 0
        private var _patches: [OnboardingPatchRequest] = []

        init(_ responses: [OnboardingStateDTO]) {
            self.responses = responses
        }

        var getCount: Int { lock.withLock { _getCount } }
        var patches: [OnboardingPatchRequest] { lock.withLock { _patches } }

        func get() async throws -> OnboardingStateDTO {
            lock.withLock {
                _getCount += 1
                let value = responses[min(cursor, responses.count - 1)]
                cursor += 1
                return value
            }
        }

        func patch(_ body: OnboardingPatchRequest) async throws -> OnboardingStateDTO {
            lock.withLock {
                _patches.append(body)
                return responses[min(cursor, responses.count - 1)]
            }
        }
    }

    /// Deterministic time. `sleep` records the requested duration and jumps
    /// the clock forward by it, so elapsed-time assertions and the 5-minute
    /// cap are exact rather than flaky.
    @MainActor
    final class FakeClock {
        private(set) var now = Date(timeIntervalSince1970: 1_700_000_000)
        private(set) var sleeps: [Duration] = []

        /// Moves the clock without yielding, so a test can age an open
        /// step without letting its polling task interleave.
        func advance(by seconds: TimeInterval) {
            now = now.addingTimeInterval(seconds)
        }

        func sleep(_ duration: Duration) async throws {
            sleeps.append(duration)
            let seconds = Double(duration.components.seconds)
                + Double(duration.components.attoseconds) * 1e-18
            now = now.addingTimeInterval(seconds)
            await Task.yield()
        }
    }

    /// Everything the coordinator reads or writes through a closure, in one
    /// mutable box so a test can script it and then inspect it.
    @MainActor
    final class World {
        var snapshot: OnboardingStateDTO?
        var pendingCaptureCount = 0
        var dismissed = false
        var setDismissedCalls: [Bool] = []
        var setDismissedError: Error?

        init(snapshot: OnboardingStateDTO? = nil) {
            self.snapshot = snapshot
        }
    }

    struct BoomError: Error {}

    // MARK: - Builder

    /// `clock` and `posthog` default to `nil` rather than to a fresh
    /// instance: a main-actor-isolated default value is evaluated through
    /// an isolation thunk that this project's language mode only warns
    /// about, and building them in the body sidesteps it entirely.
    private func makeCoordinator(
        responses: [OnboardingStateDTO],
        world: World,
        clock: FakeClock? = nil,
        posthog: ConversionFunnelTelemetryTests.FakePostHogClient? = nil
    ) -> (GuidedStartCoordinator, ScriptedOnboardingClient, FakeClock, ConversionFunnelTelemetryTests.FakePostHogClient) {
        let clock = clock ?? FakeClock()
        let posthog = posthog ?? ConversionFunnelTelemetryTests.FakePostHogClient()
        let client = ScriptedOnboardingClient(responses)
        let coordinator = GuidedStartCoordinator(
            client: client,
            telemetry: GuidedStartTelemetry(client: posthog),
            now: { clock.now },
            sleep: { try await clock.sleep($0) },
            snapshot: { world.snapshot },
            applySnapshot: { world.snapshot = $0 },
            pendingCaptureCount: { world.pendingCaptureCount },
            isDismissed: { world.dismissed },
            setDismissed: { value in
                world.setDismissedCalls.append(value)
                if let error = world.setDismissedError { throw error }
                world.dismissed = value
            }
        )
        return (coordinator, client, clock, posthog)
    }

    // MARK: - Happy path

    func testStartPollsUntilTheLatchFlipsThenCelebratesThenIdles() async {
        let world = World(snapshot: makeState())
        let (coordinator, client, clock, posthog) = makeCoordinator(
            responses: [makeState(), makeState(), makeState(capture: true)],
            world: world
        )

        await coordinator.start(.saveMemory)
        XCTAssertEqual(coordinator.phase, .active(.saveMemory, startedAt: clock.now))
        XCTAssertEqual(coordinator.requestedTab, .home)
        XCTAssertEqual(posthog.events, ["guided_start_step_started"])
        XCTAssertEqual(
            posthog.propertiesOf("guided_start_step_started"),
            ["step": .string("save_memory"), "source": .string("auto")]
        )

        await coordinator.settle()

        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertNil(coordinator.requestedTab)
        XCTAssertTrue(posthog.events.contains("guided_start_step_completed"))
        // The refresh in `start` plus two polls: the first returns an
        // unflipped snapshot, the second flips it.
        XCTAssertEqual(client.getCount, 3)
        XCTAssertEqual(world.snapshot?.firstCaptureCompleted, true)
        // Not the last step, so no confetti and no wizard-completed event.
        XCTAssertEqual(coordinator.confettiTrigger, 0)
        XCTAssertFalse(posthog.events.contains("guided_start_completed"))
    }

    func testPollScheduleIsOneTwoFourEightThenTen() async {
        let world = World(snapshot: makeState())
        let flipped = makeState(capture: true)
        let (coordinator, _, clock, _) = makeCoordinator(
            // Six unflipped answers, so the loop runs past the backoff
            // ramp and into the steady 10s cadence before completing.
            responses: [makeState(), makeState(), makeState(), makeState(),
                        makeState(), makeState(), flipped],
            world: world
        )

        await coordinator.start(.saveMemory)
        await coordinator.settle()

        XCTAssertEqual(
            Array(clock.sleeps.prefix(6)),
            [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(10), .seconds(10)]
        )
    }

    func testCompletingTheLastStepFinishesTheWizardWithConfetti() async {
        let almost = makeState(capture: true, compile: true)
        let world = World(snapshot: almost)
        let (coordinator, _, _, posthog) = makeCoordinator(
            responses: [almost, makeState(capture: true, compile: true, query: true)],
            world: world
        )

        await coordinator.start(.ask)
        XCTAssertEqual(coordinator.requestedTab, .chat)

        await coordinator.settle()

        XCTAssertEqual(coordinator.phase, .finished)
        XCTAssertEqual(coordinator.confettiTrigger, 1)
        XCTAssertTrue(posthog.events.contains("guided_start_completed"))
        XCTAssertTrue(coordinator.progress.isAllDone)
    }

    // MARK: - Skip

    func testSkipEmitsSkippedWithElapsedAndReturnsToIdle() async {
        let world = World(snapshot: makeState())
        let (coordinator, _, clock, posthog) = makeCoordinator(
            responses: [makeState()],
            world: world
        )

        await coordinator.start(.saveMemory)
        clock.advance(by: 3)
        coordinator.skip()

        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertNil(coordinator.requestedTab)
        XCTAssertEqual(
            posthog.propertiesOf("guided_start_step_skipped"),
            ["step": .string("save_memory"), "elapsed_ms": .int(3_000)]
        )

        await coordinator.settle()
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertFalse(posthog.events.contains("guided_start_step_completed"))
    }

    // MARK: - Timeout

    func testTimeoutEmitsTimedOutAndClosesQuietly() async {
        let world = World(snapshot: makeState())
        let (coordinator, _, clock, posthog) = makeCoordinator(
            // Never flips.
            responses: [makeState()],
            world: world
        )
        let startedAt = clock.now

        await coordinator.start(.saveMemory)
        await coordinator.settle()

        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertNil(coordinator.requestedTab)
        XCTAssertTrue(posthog.events.contains("guided_start_step_timed_out"))
        XCTAssertEqual(
            posthog.propertiesOf("guided_start_step_timed_out")?["step"],
            .string("save_memory")
        )
        // Gave up at the first poll at or past the 5-minute cap, and not
        // one tick later.
        let elapsed = clock.now.timeIntervalSince(startedAt)
        XCTAssertGreaterThanOrEqual(elapsed, 300)
        XCTAssertLessThan(elapsed, 315)
        XCTAssertFalse(posthog.events.contains("guided_start_step_completed"))
    }

    // MARK: - Completed elsewhere

    func testLatchFlippingWithoutALocalActionIsCompletedElsewhere() async {
        let world = World(snapshot: makeState())
        let (coordinator, _, _, posthog) = makeCoordinator(
            responses: [makeState(), makeState(capture: true)],
            world: world
        )

        await coordinator.start(.saveMemory)
        await coordinator.settle()

        XCTAssertEqual(
            posthog.propertiesOf("guided_start_step_completed")?["completed_elsewhere"],
            .bool(true)
        )
    }

    func testNoteUserActionPollsImmediatelyAndIsNotCompletedElsewhere() async {
        let world = World(snapshot: makeState())
        let (coordinator, client, clock, posthog) = makeCoordinator(
            responses: [makeState(), makeState(capture: true)],
            world: world
        )

        await coordinator.start(.saveMemory)
        let getsBefore = client.getCount

        coordinator.noteUserAction(.saveMemory)
        await coordinator.settle()

        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(
            posthog.propertiesOf("guided_start_step_completed")?["completed_elsewhere"],
            .bool(false)
        )
        // The local signal produced a poll without waiting for a tick:
        // exactly one extra GET, and the 1s backoff never ran.
        XCTAssertEqual(client.getCount, getsBefore + 1)
        XCTAssertFalse(clock.sleeps.contains(.seconds(1)))
    }

    func testNoteUserActionForAnInactiveStepIsIgnored() async {
        let world = World(snapshot: makeState())
        let (coordinator, client, _, _) = makeCoordinator(
            responses: [makeState()],
            world: world
        )

        coordinator.noteUserAction(.ask)
        await coordinator.settle()

        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(client.getCount, 0)
    }

    // MARK: - Step 2 guard

    func testSyncLearnRefusesToStartWhenNothingIsPending() async {
        let world = World(snapshot: makeState(capture: true))
        world.pendingCaptureCount = 0
        let (coordinator, _, _, posthog) = makeCoordinator(
            responses: [makeState(capture: true)],
            world: world
        )

        await coordinator.start(.syncLearn)

        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertNil(coordinator.requestedTab)
        XCTAssertEqual(coordinator.inlineMessage, GuidedStartCopy.nothingPending)
        XCTAssertFalse(posthog.events.contains("guided_start_step_started"))
    }

    func testSyncLearnStartsWhenSomethingIsPending() async {
        let world = World(snapshot: makeState(capture: true))
        world.pendingCaptureCount = 2
        let (coordinator, _, clock, posthog) = makeCoordinator(
            responses: [makeState(capture: true)],
            world: world
        )

        await coordinator.start(.syncLearn)

        XCTAssertEqual(coordinator.phase, .active(.syncLearn, startedAt: clock.now))
        XCTAssertNil(coordinator.inlineMessage)
        XCTAssertEqual(
            posthog.propertiesOf("guided_start_step_started")?["step"],
            .string("sync_learn")
        )

        coordinator.skip()
        await coordinator.settle()
    }

    // MARK: - Start refreshes and skips ahead

    func testStartingAStepWhoseLatchIsAlreadyTrueSkipsAhead() async {
        // The card still shows step 1 as next, but the server already has
        // the capture latched — start step 2 instead of teaching a
        // finished thing.
        let world = World(snapshot: makeState())
        world.pendingCaptureCount = 1
        let (coordinator, _, clock, posthog) = makeCoordinator(
            responses: [makeState(capture: true)],
            world: world
        )

        await coordinator.start(.saveMemory)

        XCTAssertEqual(coordinator.phase, .active(.syncLearn, startedAt: clock.now))
        XCTAssertEqual(
            posthog.propertiesOf("guided_start_step_started")?["step"],
            .string("sync_learn")
        )

        coordinator.skip()
        await coordinator.settle()
    }

    func testStartingWhenTheRefreshShowsEverythingDoneFinishesInstead() async {
        let world = World(snapshot: makeState())
        let (coordinator, _, _, posthog) = makeCoordinator(
            responses: [makeState(capture: true, compile: true, query: true)],
            world: world
        )

        await coordinator.start(.saveMemory)

        XCTAssertEqual(coordinator.phase, .finished)
        XCTAssertFalse(posthog.events.contains("guided_start_step_started"))
        XCTAssertTrue(posthog.events.contains("guided_start_completed"))
    }

    // MARK: - Dismissal seam

    func testDismissHidesOptimisticallyThenPersists() async {
        let world = World(snapshot: makeState())
        let (coordinator, _, _, posthog) = makeCoordinator(
            responses: [makeState()],
            world: world
        )
        XCTAssertTrue(coordinator.isCardVisible)

        await coordinator.dismissCard()

        XCTAssertFalse(coordinator.isCardVisible)
        XCTAssertEqual(world.setDismissedCalls, [true])
        XCTAssertTrue(world.dismissed)
        XCTAssertTrue(posthog.events.contains("guided_start_dismissed"))
    }

    func testDismissFailureUnhidesAndSaysSo() async {
        let world = World(snapshot: makeState())
        world.setDismissedError = BoomError()
        let (coordinator, _, _, _) = makeCoordinator(
            responses: [makeState()],
            world: world
        )

        await coordinator.dismissCard()

        XCTAssertTrue(coordinator.isCardVisible)
        XCTAssertFalse(world.dismissed)
        XCTAssertNotNil(coordinator.inlineMessage)
    }

    func testShowMeAroundClearsDismissal() async {
        let world = World(snapshot: makeState())
        world.dismissed = true
        let (coordinator, _, _, posthog) = makeCoordinator(
            responses: [makeState()],
            world: world
        )
        XCTAssertFalse(coordinator.isCardVisible)

        await coordinator.showMeAround()

        XCTAssertTrue(coordinator.isCardVisible)
        XCTAssertEqual(world.setDismissedCalls, [false])
        XCTAssertFalse(world.dismissed)
        XCTAssertEqual(
            posthog.propertiesOf("guided_start_reopened"),
            ["source": .string("settings")]
        )
    }

    /// "If everything is already done, show the completed card for that
    /// session only — do not persist a way to re-enter a finished wizard."
    func testShowMeAroundOnAFinishedWizardIsSessionOnly() async {
        let done = makeState(capture: true, compile: true, query: true)
        let world = World(snapshot: done)
        world.dismissed = true
        let (coordinator, _, _, _) = makeCoordinator(responses: [done], world: world)

        await coordinator.showMeAround()

        XCTAssertTrue(coordinator.isCardVisible)
        // A coordinator rebuilt next launch sees the same world and hides.
        let (fresh, _, _, _) = makeCoordinator(responses: [done], world: world)
        XCTAssertFalse(fresh.isCardVisible)
    }

    /// Dismissal from another device must not yank the card out from under
    /// an open step.
    func testRemoteDismissalWaitsForTheOpenStepToFinish() async {
        let world = World(snapshot: makeState())
        let (coordinator, _, _, _) = makeCoordinator(
            responses: [makeState(), makeState(), makeState(capture: true)],
            world: world
        )

        await coordinator.start(.saveMemory)
        world.dismissed = true
        XCTAssertTrue(coordinator.isCardVisible)

        coordinator.skip()
        XCTAssertFalse(coordinator.isCardVisible)

        await coordinator.settle()
    }

    // MARK: - Visibility truth table

    func testIsCardVisibleTruthTable() async {
        let unfinished = makeState(capture: true)
        let done = makeState(capture: true, compile: true, query: true)

        // loaded, allDone, dismissed -> visible
        let cases: [(OnboardingStateDTO?, Bool, Bool)] = [
            (nil, false, false),
            (nil, true, false),
            (unfinished, false, true),
            (unfinished, true, false),
            (done, false, false),
            (done, true, false),
        ]

        for (snapshot, dismissed, expected) in cases {
            let world = World(snapshot: snapshot)
            world.dismissed = dismissed
            let (coordinator, _, _, _) = makeCoordinator(
                responses: [snapshot ?? makeState()],
                world: world
            )
            XCTAssertEqual(
                coordinator.isCardVisible,
                expected,
                "loaded=\(snapshot != nil) allDone=\(GuidedStartProgress(snapshot).isAllDone) dismissed=\(dismissed)"
            )
        }
    }

    // MARK: - Card shown

    func testCardShownFiresOncePerSession() async {
        let world = World(snapshot: makeState())
        let (coordinator, _, _, posthog) = makeCoordinator(
            responses: [makeState()],
            world: world
        )

        coordinator.noteCardShown()
        coordinator.noteCardShown()
        coordinator.noteCardShown()

        XCTAssertEqual(posthog.events.filter { $0 == "guided_start_card_shown" }.count, 1)
    }

    func testCardShownDoesNotFireWhenTheCardIsNotVisible() async {
        let world = World(snapshot: nil)
        let (coordinator, _, _, posthog) = makeCoordinator(
            responses: [makeState()],
            world: world
        )

        coordinator.noteCardShown()

        XCTAssertTrue(posthog.events.isEmpty)
    }

    // MARK: - Refresh

    func testRefreshAppliesTheSnapshot() async {
        let world = World(snapshot: nil)
        let (coordinator, client, _, _) = makeCoordinator(
            responses: [makeState(capture: true)],
            world: world
        )

        await coordinator.refresh()

        XCTAssertEqual(client.getCount, 1)
        XCTAssertEqual(world.snapshot?.firstCaptureCompleted, true)
        XCTAssertEqual(coordinator.progress.next, .syncLearn)
    }

    func testRefreshKeepsStaleStateWhenTheFetchFails() async {
        let world = World(snapshot: makeState())
        let failing = FailingOnboardingClient()
        let clock = FakeClock()
        let coordinator = GuidedStartCoordinator(
            client: failing,
            telemetry: GuidedStartTelemetry(client: ConversionFunnelTelemetryTests.FakePostHogClient()),
            now: { clock.now },
            sleep: { try await clock.sleep($0) },
            snapshot: { world.snapshot },
            applySnapshot: { world.snapshot = $0 },
            pendingCaptureCount: { world.pendingCaptureCount },
            isDismissed: { world.dismissed },
            setDismissed: { _ in }
        )

        await coordinator.refresh()

        XCTAssertNotNil(world.snapshot)
        XCTAssertTrue(coordinator.isCardVisible)
    }

    final class FailingOnboardingClient: OnboardingClientProtocol, @unchecked Sendable {
        struct Boom: Error {}
        func get() async throws -> OnboardingStateDTO { throw Boom() }
        func patch(_ body: OnboardingPatchRequest) async throws -> OnboardingStateDTO { throw Boom() }
    }
}

// MARK: - Fixture

private func makeState(
    capture: Bool = false,
    compile: Bool = false,
    query: Bool = false
) -> OnboardingStateDTO {
    makeStepState(capture: capture, compile: compile, query: query)
}
