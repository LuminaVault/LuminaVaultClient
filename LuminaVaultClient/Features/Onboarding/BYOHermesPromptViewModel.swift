// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/BYOHermesPromptViewModel.swift
//
// HER-219 — view model for the optional BYO-Hermes onboarding step.
// Fires three telemetry events (`onboarding.byo_hermes.shown`,
// `onboarding.byo_hermes.set_up_now`, `onboarding.byo_hermes.skipped`)
// and notifies the parent coordinator via callbacks. No persistence —
// this step is idempotent and has no `OnboardingState` latch.

import Foundation

@Observable
@MainActor
final class BYOHermesPromptViewModel {
    /// Names of the telemetry events this view emits. Centralised so
    /// tests + downstream analytics dashboards can reference them.
    enum Event {
        static let shown = "onboarding.byo_hermes.shown"
        static let setUpNow = "onboarding.byo_hermes.set_up_now"
        static let skipped = "onboarding.byo_hermes.skipped"
    }

    private let telemetry: any TelemetryProtocol
    private let onSetUpNow: @MainActor () -> Void
    private let onSkip: @MainActor () -> Void

    /// Set after `onAppear` runs once so re-entering the screen (e.g.
    /// returning from the Settings deep-link) does not duplicate the
    /// `.shown` event.
    private(set) var hasFiredShownEvent = false

    init(
        telemetry: any TelemetryProtocol,
        onSetUpNow: @escaping @MainActor () -> Void,
        onSkip: @escaping @MainActor () -> Void,
    ) {
        self.telemetry = telemetry
        self.onSetUpNow = onSetUpNow
        self.onSkip = onSkip
    }

    /// Call from `.onAppear`. Records the impression exactly once.
    func onAppear() {
        guard !hasFiredShownEvent else { return }
        hasFiredShownEvent = true
        telemetry.track(Event.shown)
    }

    /// "Set up now →" tap. Emits the telemetry event then hands control
    /// to the coordinator, which deep-links into Settings → Hermes Gateway.
    func setUpNowTapped() {
        telemetry.track(Event.setUpNow)
        onSetUpNow()
    }

    /// "Skip" tap. Emits the telemetry event then advances the coordinator.
    /// No server-side state change.
    func skipTapped() {
        telemetry.track(Event.skipped)
        onSkip()
    }
}
