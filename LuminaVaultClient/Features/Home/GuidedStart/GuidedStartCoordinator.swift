// LuminaVaultClient/LuminaVaultClient/Features/Home/GuidedStart/GuidedStartCoordinator.swift
//
// The phase machine behind "Get started with Hermie". Pure logic: no
// views, no AppState, no anchors. `docs/guided-start.md` is the contract
// and wins over anything inferred here.
//
// Everything the coordinator touches comes in through the initializer as
// a protocol or a closure, which is what lets the whole suite run in
// microseconds: the poll waits go through an injected `sleep`, and the
// 5-minute cap is measured against an injected `now`.
//
// ## The dismissal seam
//
// `isDismissed` / `setDismissed` are deliberately a closure pair rather
// than a read of the snapshot. The contract puts dismissal on
// `OnboardingStateDTO.guidedStartDismissedAt` — a nullable timestamp set
// and cleared through `PATCH /v1/onboarding` with `guidedStartDismissed`,
// the only two-way field on that endpoint — but that field is not in
// `LuminaVaultShared` yet; it lands in a later slice, behind work this
// branch must not touch.
//
// So the composition root supplies whatever backing exists today, and
// once the DTO ships it becomes:
//
//     isDismissed:  { appState.onboardingState?.guidedStartDismissedAt != nil }
//     setDismissed: { try await onboardingClient.patch(
//                         OnboardingPatchRequest(guidedStartDismissed: $0)) }
//
// Nothing in this file, and nothing at a call site, learns the
// difference. `refresh()` reconciles a dismissal made on another device
// for free at that point, because `isDismissed` will be reading the same
// snapshot `refresh()` just applied.
//
// ## What is deliberately absent
//
// The card view, the spotlight overlay, and the anchor plumbing. A
// parallel spike owns how anchors propagate; `requestedTab` and
// `GuidedTarget` are the only hooks this layer offers it.

import Foundation
import LuminaVaultShared
import Observation

/// The coordinator's own tab vocabulary.
///
/// `AppTab` is declared inside `MainTabView`, so depending on it would
/// tie this pure-logic core to a SwiftUI view. The integration slice maps
/// `.home -> MainTabView.AppTab.home` and `.chat -> MainTabView.AppTab.think`
/// (the "AI" tab, which hosts the chat composer).
enum GuidedTab: String, Sendable {
    case home
    case chat
}

@MainActor
@Observable
final class GuidedStartCoordinator {

    // MARK: - Phase

    enum Phase: Equatable {
        case idle
        case active(GuidedStartStep, startedAt: Date)
        case celebrating(GuidedStartStep)
        case finished

        /// The card stays on screen while any of these hold, even if a
        /// dismissal arrives from another device mid-step.
        var isEngaged: Bool {
            if case .idle = self { return false }
            return true
        }
    }

    // MARK: - Schedule

    /// 1s, 2s, 4s, 8s, then every 10s, giving up after 5 minutes.
    private static let pollBackoff: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8)]
    private static let pollSteadyState: Duration = .seconds(10)
    private static let stepTimeout: TimeInterval = 300
    /// How long Hermie stays happy before the card goes back to resting.
    private static let celebrationDwell: Duration = .milliseconds(1_600)

    // MARK: - Published state

    private(set) var phase: Phase = .idle
    /// A line the card shows in place of starting a step — the "Save
    /// something first" guard, or a failed dismiss.
    private(set) var inlineMessage: String?
    /// Set when an open step lives on another tab. The shell consumes it
    /// and is expected to clear nothing; the coordinator clears it when
    /// the step ends.
    private(set) var requestedTab: GuidedTab?
    /// Bumped once when the final step completes. Views watch for the
    /// change rather than a bool so a repeat is impossible.
    private(set) var confettiTrigger = 0

    // MARK: - Injected world

    private let client: any OnboardingClientProtocol
    private let telemetry: GuidedStartTelemetry
    private let now: @MainActor () -> Date
    private let sleep: @MainActor (Duration) async throws -> Void
    private let snapshot: @MainActor () -> OnboardingStateDTO?
    private let applySnapshot: @MainActor (OnboardingStateDTO) -> Void
    private let pendingCaptureCount: @MainActor () async throws -> Int
    private let isDismissedSeam: @MainActor () -> Bool
    private let setDismissedSeam: @MainActor (Bool) async throws -> Void

    // MARK: - Bookkeeping

    /// Local optimistic value that shadows the seam between a dismiss tap
    /// and the PATCH settling. `nil` means "trust the seam".
    @ObservationIgnored private var dismissOverride: Bool?
    /// Settings › "Show me around" on an already-finished wizard shows the
    /// completed card for this session only, and persists nothing.
    @ObservationIgnored private var sessionShowsCompletedCard = false
    @ObservationIgnored private var didFireCardShown = false
    /// Steps the user visibly did on this device. Their absence is what
    /// makes a completion `completed_elsewhere`.
    @ObservationIgnored private var locallyActed: Set<GuidedStartStep> = []
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var workGeneration = 0
    /// Bumped whenever a run is superseded, so a task that is already
    /// past its cancellation check cannot write state for a dead step.
    @ObservationIgnored private var runID = 0
    /// Where the current run is in the backoff ramp, so an immediate poll
    /// triggered by a local signal resumes the schedule instead of
    /// restarting it.
    @ObservationIgnored private var pollIndex = 0

    // MARK: - Init

    init(
        client: any OnboardingClientProtocol,
        telemetry: GuidedStartTelemetry,
        now: @MainActor @escaping () -> Date = { Date() },
        sleep: @MainActor @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        snapshot: @MainActor @escaping () -> OnboardingStateDTO?,
        applySnapshot: @MainActor @escaping (OnboardingStateDTO) -> Void,
        /// **Must perform a fresh read** of the unprocessed-vault-row count
        /// every time it is called — `KBCompileClientProtocol.pending()` or
        /// equivalent. Do not wire it to a cached view-model value such as
        /// `HomeGlanceViewModel.recommendation`: that value is loaded when
        /// Home appears and never polls, so a memory saved since then makes
        /// it stale, and a stale zero opens a spotlight that cannot end in
        /// anything but the 5-minute timeout.
        ///
        /// Throwing means "cannot determine right now", and the step starts
        /// anyway — refusing on a failed probe would be worse than starting
        /// on an unknown one.
        pendingCaptureCount: @MainActor @escaping () async throws -> Int,
        isDismissed: @MainActor @escaping () -> Bool,
        setDismissed: @MainActor @escaping (Bool) async throws -> Void
    ) {
        self.client = client
        self.telemetry = telemetry
        self.now = now
        self.sleep = sleep
        self.snapshot = snapshot
        self.applySnapshot = applySnapshot
        self.pendingCaptureCount = pendingCaptureCount
        self.isDismissedSeam = isDismissed
        self.setDismissedSeam = setDismissed
    }

    /// A poll that is merely waiting holds this object weakly, so losing
    /// the last owning reference gets us here promptly — but the task is
    /// still parked in `sleep`, and on the real clock that park is up to
    /// ten seconds long. Cancelling makes `Task.sleep` throw immediately
    /// instead of letting a torn-down screen keep polling.
    deinit {
        work?.cancel()
    }

    // MARK: - Derived state

    var progress: GuidedStartProgress { GuidedStartProgress(snapshot()) }

    var isDismissed: Bool { dismissOverride ?? isDismissedSeam() }

    /// `loaded && !allDone && !dismissed`, plus the two session-scoped
    /// exceptions the contract calls for: an open step keeps the card up
    /// even if a dismissal arrives from elsewhere, and "Show me around"
    /// can re-show a finished card for this session.
    var isCardVisible: Bool {
        guard snapshot() != nil else { return false }
        if phase.isEngaged { return true }
        if isDismissed { return false }
        if progress.isAllDone { return sessionShowsCompletedCard }
        return true
    }

    // MARK: - Card lifecycle

    /// Call from the card's `onAppear`. Fires `guided_start_card_shown`
    /// once per app session, not once per render.
    func noteCardShown() {
        guard isCardVisible, !didFireCardShown else { return }
        didFireCardShown = true
        telemetry.cardShown()
    }

    /// Pull the current ladder. Failures keep the stale snapshot rather
    /// than blanking the card, which would flash it away on a flaky
    /// network.
    func refresh() async {
        guard let state = try? await client.get() else { return }
        applySnapshot(state)
    }

    // MARK: - Steps

    /// Refreshes first, then opens `step` — or the first incomplete step,
    /// if the server says this one is already done.
    func start(_ step: GuidedStartStep, source: GuidedStartSource = .auto) async {
        inlineMessage = nil
        cancelWork()
        await refresh()

        guard let target = resolveStart(step) else {
            // Everything latched while we were not looking.
            finishWizard()
            return
        }

        // An empty compile returns early server-side and never latches,
        // so opening step 2 with nothing pending would strand the user in
        // a spotlight that cannot finish. The count is read *here*, live,
        // rather than trusting whatever the surrounding view had cached.
        // A throw means "cannot determine", and is not grounds to refuse.
        if target == .syncLearn, let pending = try? await pendingCaptureCount(), pending == 0 {
            inlineMessage = GuidedStartCopy.nothingPending
            return
        }

        let startedAt = now()
        locallyActed.remove(target)
        pollIndex = 0
        runID += 1
        let run = runID

        phase = .active(target, startedAt: startedAt)
        requestedTab = tab(for: target)
        telemetry.stepStarted(target, source: source)

        startPolling(target, startedAt: startedAt, run: run, delayIndex: 0, pollImmediately: false)
    }

    /// Skip is a real action, not a dismiss: the card stays, this step
    /// closes.
    func skip() {
        guard case .active(let step, let startedAt) = phase else { return }
        cancelWork()
        runID += 1
        telemetry.stepSkipped(step, elapsedMs: elapsedMs(since: startedAt))
        closeStep()
    }

    /// A local signal that the user just did the thing. Triggers an
    /// immediate poll instead of waiting for the next tick, and marks the
    /// eventual completion as *not* `completed_elsewhere`.
    func noteUserAction(_ step: GuidedStartStep) {
        locallyActed.insert(step)
        guard case .active(let current, let startedAt) = phase, current == step else { return }
        let resumeIndex = pollIndex
        cancelWork()
        runID += 1
        let run = runID
        startPolling(
            step,
            startedAt: startedAt,
            run: run,
            delayIndex: resumeIndex,
            pollImmediately: true
        )
    }

    // MARK: - Dismissal

    /// Hides optimistically, then persists. On failure the card comes
    /// back and says so, rather than silently reappearing next launch.
    func dismissCard() async {
        dismissOverride = true
        inlineMessage = nil
        telemetry.dismissed()
        do {
            try await setDismissedSeam(true)
        } catch {
            dismissOverride = nil
            inlineMessage = GuidedStartCopy.dismissFailed
        }
    }

    /// Settings › "Show me around". Clears the dismissal. If the wizard is
    /// already finished the card comes back for this session only — the
    /// cleared dismissal does not amount to a way to re-enter it, because
    /// `allDone` still hides it on the next launch.
    func showMeAround() async {
        dismissOverride = false
        inlineMessage = nil
        if progress.isAllDone { sessionShowsCompletedCard = true }
        telemetry.reopened()
        do {
            try await setDismissedSeam(false)
        } catch {
            dismissOverride = nil
        }
    }

    // MARK: - Polling

    private enum Tick { case keepGoing, stop }

    /// Owns the wait loop. The loop body deliberately does *not* live in a
    /// method on `self`: `await self?.method()` resolves the weak
    /// reference into a strong one for the whole call, so a single
    /// `runStep`-shaped method would pin the coordinator alive for the
    /// entire step — up to the full five-minute cap — after the owning
    /// view had been torn down.
    ///
    /// Here the coordinator is only held while a tick is doing work. The
    /// waits run against a captured copy of the `sleep` closure and hold
    /// nothing, so dropping the last owning reference reaches `deinit`,
    /// which cancels this task out of its wait.
    private func startPolling(
        _ step: GuidedStartStep,
        startedAt: Date,
        run: Int,
        delayIndex: Int,
        pollImmediately: Bool
    ) {
        let sleep = self.sleep
        let backoff = Self.pollBackoff
        let steady = Self.pollSteadyState

        workGeneration += 1
        work = Task { [weak self] in
            var index = delayIndex
            var immediate = pollImmediately

            while true {
                if Task.isCancelled { return }

                if immediate {
                    immediate = false
                } else {
                    let delay = index < backoff.count ? backoff[index] : steady
                    index += 1
                    self?.notePollIndex(index)
                    do { try await sleep(delay) } catch { return }
                }

                guard let tick = await self?.pollTick(step, startedAt: startedAt, run: run) else { return }
                if tick == .stop { return }
            }
        }
    }

    /// One poll: fetch, apply, and decide whether the step is done, timed
    /// out, or should keep waiting.
    private func pollTick(_ step: GuidedStartStep, startedAt: Date, run: Int) async -> Tick {
        guard isRunning(step, run: run) else { return .stop }

        if let state = try? await client.get() {
            guard isRunning(step, run: run) else { return .stop }
            applySnapshot(state)
            if step.isComplete(in: state) {
                await complete(step, startedAt: startedAt)
                return .stop
            }
        }

        guard isRunning(step, run: run) else { return .stop }
        if now().timeIntervalSince(startedAt) >= Self.stepTimeout {
            telemetry.stepTimedOut(step, elapsedMs: elapsedMs(since: startedAt))
            closeStep()
            return .stop
        }
        return .keepGoing
    }

    /// Where the ramp has got to, so a local signal can poll immediately
    /// and then resume the schedule rather than restart it.
    private func notePollIndex(_ index: Int) {
        pollIndex = index
    }

    private func complete(_ step: GuidedStartStep, startedAt: Date) async {
        let elsewhere = !locallyActed.contains(step)
        telemetry.stepCompleted(
            step,
            elapsedMs: elapsedMs(since: startedAt),
            completedElsewhere: elsewhere
        )
        locallyActed.remove(step)
        requestedTab = nil
        phase = .celebrating(step)

        // The snapshot was applied before we got here, so this reads the
        // ladder that just changed.
        let allDone = progress.isAllDone
        if allDone { confettiTrigger += 1 }

        try? await sleep(Self.celebrationDwell)
        guard case .celebrating(let current) = phase, current == step else { return }
        if allDone {
            phase = .finished
            telemetry.completed()
        } else {
            phase = .idle
        }
    }

    // MARK: - Helpers

    /// The step to actually open: the requested one, or the first
    /// incomplete one if the server already has this one latched. `nil`
    /// means there is nothing left to teach.
    private func resolveStart(_ step: GuidedStartStep) -> GuidedStartStep? {
        guard let state = snapshot() else { return step }
        if !step.isComplete(in: state) { return step }
        return progress.next
    }

    private func finishWizard() {
        guard phase != .finished else { return }
        requestedTab = nil
        phase = .finished
        telemetry.completed()
    }

    private func closeStep() {
        requestedTab = nil
        inlineMessage = nil
        phase = .idle
    }

    private func isRunning(_ step: GuidedStartStep, run: Int) -> Bool {
        guard !Task.isCancelled, run == runID else { return false }
        guard case .active(let current, _) = phase, current == step else { return false }
        return true
    }

    private func tab(for step: GuidedStartStep) -> GuidedTab {
        switch step.target {
        case .composer, .sync: .home
        case .chat:            .chat
        }
    }

    private func elapsedMs(since startedAt: Date) -> Int {
        Int((now().timeIntervalSince(startedAt) * 1_000).rounded())
    }

    private func cancelWork() {
        work?.cancel()
        work = nil
    }

    // MARK: - Test seam

    #if DEBUG
    /// Awaits whatever run is in flight, including a run that replaced the
    /// one we started waiting on. Tests only, and not shipped: production
    /// code never needs to know when polling settles.
    func settle() async {
        for _ in 0..<64 {
            guard let task = work else { return }
            let generation = workGeneration
            await task.value
            if workGeneration == generation {
                work = nil
                return
            }
        }
    }
    #endif
}
