// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Conversion/ConversionFunnelState.swift
//
// HER-287 — @Observable state for the conversion onboarding funnel.
// Holds the current step + every answer the user gives. The container
// view binds against this; individual screens mutate it via typed
// setters so the navigation contract stays narrow.
//
// Resumability: when the app is killed mid-funnel, the next launch
// picks up at `currentStep` (read from UserDefaults via the container's
// @AppStorage gate). Answers themselves are intentionally in-memory
// only — replaying the funnel from any earlier step is cheap, and
// persisting the answer payload would couple this to a schema.

import Foundation
import Observation

@MainActor
@Observable
final class ConversionFunnelState {
    // MARK: - Position

    var currentStep: ConversionFunnelStep = .welcome

    // MARK: - Screen 2: Goal

    var selectedGoal: FunnelGoal?

    // MARK: - Screen 3: Pain points

    var selectedPains: Set<FunnelPainPoint> = []

    // MARK: - Screen 5: Swipe cards

    /// Cards the user swiped right on (agreed with). Order matches
    /// `FunnelSwipeCard.all`.
    var swipeAgreements: Set<Int> = []
    /// Cards the user swiped left on (dismissed). Recorded for symmetry
    /// + future analytics — currently unused by downstream screens.
    var swipeDismissals: Set<Int> = []

    // MARK: - Screen 8: Capture sources

    var selectedCaptureSources: Set<FunnelCaptureSource> = []

    // MARK: - Screen 10: App demo picks

    /// Sample captures the user swiped right on during the demo.
    /// Bounded to 3 by the screen's logic; the type doesn't enforce it
    /// so tests can assert behaviour at the boundary.
    private(set) var demoPickedCaptureIDs: [UUID] = []

    // MARK: - HER-295 telemetry

    /// PostHog wrapper. Injected so tests can substitute a fake without
    /// dragging the SDK into the test target (mirrors `purchasesProxyFactory`).
    @ObservationIgnored private let telemetry: ConversionFunnelTelemetry
    /// Clock seam — tests inject a deterministic source so duration_ms
    /// assertions don't rely on `Date()`.
    @ObservationIgnored private let now: @MainActor () -> Date
    /// Stamped on every step transition; subtracted on advance to
    /// produce `duration_ms`.
    @ObservationIgnored private var enteredCurrentStepAt: Date
    /// Stamped on init; used by `completionSummary` for total_duration_ms.
    @ObservationIgnored private let startedAt: Date

    init(
        telemetry: ConversionFunnelTelemetry = ConversionFunnelTelemetry(),
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.telemetry = telemetry
        self.now = now
        let t0 = now()
        self.enteredCurrentStepAt = t0
        self.startedAt = t0
        // Fire the initial view event for `.welcome` so the funnel chart
        // starts at the first screen with no off-by-one drop.
        telemetry.view(step: .welcome)
    }

    // MARK: - Step gating

    /// Returns true when the user has given enough input to advance
    /// from the current step. The container reads this to enable /
    /// disable the primary CTA.
    var canAdvanceFromCurrentStep: Bool {
        switch currentStep {
        case .welcome:              return true
        case .goal:                 return selectedGoal != nil
        case .painPoints:           return true     // skippable
        case .socialProof:          return true
        case .swipeCards:           return true     // auto-advance, never blocked
        case .personalisedSolution: return true
        case .comparison:           return true
        case .captureSources:       return true     // skippable; demo falls back to all sources
        case .processing:           return true     // auto-advance
        case .appDemo:              return demoPickedCaptureIDs.count >= 3
        case .valueDelivery:        return true
        case .notificationPrime:    return true     // both Enable and "Not now" advance
        }
    }

    // MARK: - Navigation

    func advance() {
        guard canAdvanceFromCurrentStep, let next = currentStep.next else { return }
        let from = currentStep
        let durationMs = millisecondsSinceEnteredCurrentStep()
        telemetry.advance(step: from, durationMs: durationMs)
        transition(to: next)
    }

    func goBack() {
        guard let previous = currentStep.previous else { return }
        telemetry.back(step: currentStep)
        transition(to: previous)
    }

    /// Single source of truth for step transitions. Stamps the new
    /// enter-time and fires the `view` event so every step shift records
    /// both a view + (on the next advance) a duration.
    private func transition(to step: ConversionFunnelStep) {
        currentStep = step
        enteredCurrentStepAt = now()
        telemetry.view(step: step)
    }

    private func millisecondsSinceEnteredCurrentStep() -> Int {
        let elapsed = now().timeIntervalSince(enteredCurrentStepAt)
        return Int((elapsed * 1000).rounded())
    }

    // MARK: - Mutations (called from screen views)

    func selectGoal(_ goal: FunnelGoal) {
        selectedGoal = goal
        telemetry.answerGoal(goal)
    }

    func togglePain(_ pain: FunnelPainPoint) {
        if selectedPains.contains(pain) {
            selectedPains.remove(pain)
        } else {
            selectedPains.insert(pain)
        }
        telemetry.answerPain(set: selectedPains)
    }

    func recordSwipe(cardID: Int, agreed: Bool) {
        if agreed {
            swipeAgreements.insert(cardID)
            swipeDismissals.remove(cardID)
        } else {
            swipeDismissals.insert(cardID)
            swipeAgreements.remove(cardID)
        }
        telemetry.answerSwipe(cardID: cardID, agreed: agreed)
    }

    func toggleCaptureSource(_ source: FunnelCaptureSource) {
        if selectedCaptureSources.contains(source) {
            selectedCaptureSources.remove(source)
        } else {
            selectedCaptureSources.insert(source)
        }
        telemetry.answerCaptureSources(selectedCaptureSources)
    }

    func recordDemoPick(captureID: UUID) {
        guard demoPickedCaptureIDs.count < 3,
              !demoPickedCaptureIDs.contains(captureID) else { return }
        demoPickedCaptureIDs.append(captureID)
        telemetry.answerDemoPick(captureID: captureID)
    }

    /// Used by tests + the "back" gesture on the demo screen.
    func resetDemoPicks() {
        demoPickedCaptureIDs.removeAll()
    }

    // MARK: - HER-295 completion payload

    /// Snapshot of the user's answers + total elapsed time. Caller (the
    /// `LuminaVaultClientApp` Screen-12 resolution) fires the
    /// `onboarding_funnel_completed` event with this payload.
    func completionSummary() -> ConversionFunnelCompletionSummary {
        let elapsed = now().timeIntervalSince(startedAt)
        return ConversionFunnelCompletionSummary(
            totalDurationMs: Int((elapsed * 1000).rounded()),
            goal: selectedGoal?.rawValue,
            painCount: selectedPains.count,
            swipeAgreeCount: swipeAgreements.count,
            captureSourceCount: selectedCaptureSources.count
        )
    }

    /// Direct accessor for the telemetry wrapper so views that own no
    /// state (e.g. `NotificationPrimeView`, `ValueDeliveryView`) can fire
    /// their own events without duplicating the PostHog client wiring.
    var telemetryClient: ConversionFunnelTelemetry { telemetry }
}
