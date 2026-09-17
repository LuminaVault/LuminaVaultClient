// LuminaVaultClient/LuminaVaultClient/Features/Home/GuidedStart/GuidedStartTelemetry.swift
//
// The eight guided-start events from `docs/guided-start.md`.
//
// Same shape as `ConversionFunnelTelemetry`: a typed facade over the
// shared `PostHogClient` seam, everything @MainActor so the
// `[String: Any]` property dict never crosses an isolation boundary, and
// the event names in one `enum` so call sites and tests refer to the same
// taxonomy.
//
// Android emits these names verbatim and the web prefixes each with
// `web_`, so a rename here is a three-platform dashboard migration.
// Property values are the step *ids*, never the display copy.

import Foundation

// MARK: - Event names

enum GuidedStartEvent {
    static let cardShown = "guided_start_card_shown"
    static let stepStarted = "guided_start_step_started"
    static let stepCompleted = "guided_start_step_completed"
    static let stepSkipped = "guided_start_step_skipped"
    static let stepTimedOut = "guided_start_step_timed_out"
    static let dismissed = "guided_start_dismissed"
    static let reopened = "guided_start_reopened"
    static let completed = "guided_start_completed"
}

/// How the user got here: the card auto-showed on Home, or they asked for
/// it again from Settings › "Show me around".
enum GuidedStartSource: String, Sendable {
    case auto
    case settings
}

// MARK: - Telemetry

@MainActor
struct GuidedStartTelemetry {
    private let client: PostHogClient

    init(client: PostHogClient = LivePostHogClient()) {
        self.client = client
    }

    /// Fires once per app session, the first time the card renders — the
    /// coordinator owns that once-ness, not this type.
    func cardShown(source: GuidedStartSource) {
        client.capture(GuidedStartEvent.cardShown, properties: [
            "source": source.rawValue,
        ])
    }

    func stepStarted(_ step: GuidedStartStep, source: GuidedStartSource) {
        client.capture(GuidedStartEvent.stepStarted, properties: [
            "step": step.rawValue,
            "source": source.rawValue,
        ])
    }

    /// `completedElsewhere` is true when the latch flipped without a local
    /// signal that the user did the thing here — another device, or a
    /// queued capture draining. The user did it; where is not interesting
    /// beyond this flag.
    func stepCompleted(_ step: GuidedStartStep, elapsedMs: Int, completedElsewhere: Bool) {
        client.capture(GuidedStartEvent.stepCompleted, properties: [
            "step": step.rawValue,
            "elapsed_ms": elapsedMs,
            "completed_elsewhere": completedElsewhere,
        ])
    }

    func stepSkipped(_ step: GuidedStartStep, elapsedMs: Int) {
        client.capture(GuidedStartEvent.stepSkipped, properties: [
            "step": step.rawValue,
            "elapsed_ms": elapsedMs,
        ])
    }

    /// The 5-minute cap expired with the latch still false.
    func stepTimedOut(_ step: GuidedStartStep, elapsedMs: Int) {
        client.capture(GuidedStartEvent.stepTimedOut, properties: [
            "step": step.rawValue,
            "elapsed_ms": elapsedMs,
        ])
    }

    func dismissed() {
        client.capture(GuidedStartEvent.dismissed, properties: nil)
    }

    /// Settings › "Show me around" cleared the dismissal.
    func reopened() {
        client.capture(GuidedStartEvent.reopened, properties: [
            "source": GuidedStartSource.settings.rawValue,
        ])
    }

    /// All three latches true — the whole loop is taught.
    func completed() {
        client.capture(GuidedStartEvent.completed, properties: nil)
    }
}
