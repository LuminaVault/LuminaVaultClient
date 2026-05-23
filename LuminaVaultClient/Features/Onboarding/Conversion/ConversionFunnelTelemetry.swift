// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Conversion/ConversionFunnelTelemetry.swift
//
// HER-295 — typed wrapper around `PostHogSDK.shared.capture(_:properties:)`
// for the conversion-funnel events fired from `ConversionFunnelState`,
// `ConversionFunnelContainer`, `NotificationPrimeView`, `ValueDeliveryView`,
// and `LuminaVaultClientApp` Screen-12 resolution.
//
// Goals
//   1. Keep event names + property keys in a single place so call sites
//      can't fat-finger them.
//   2. Provide a `PostHogClient` test seam mirroring the
//      `purchasesProxyFactory` pattern so unit tests assert the wrapper
//      records the right names/payloads without dragging the PostHog SDK
//      into the test target.
//   3. Stay strict-concurrency clean: everything is @MainActor so the
//      `[String: Any]` properties dict never crosses an isolation boundary.

import Foundation
import PostHog

// MARK: - PostHog event names

/// String literals live here so call sites + tests refer to the same
/// taxonomy. PostHog dashboards key off these names; renaming requires
/// a coordinated dashboard update.
enum ConversionFunnelEvent {
    static let view = "onboarding_funnel_view"
    static let advance = "onboarding_funnel_advance"
    static let back = "onboarding_funnel_back"
    static let answer = "onboarding_funnel_answer"
    static let completed = "onboarding_funnel_completed"
    static let paywallShown = "onboarding_funnel_paywall_shown"
    static let notificationPrompted = "onboarding_funnel_notification_prompted"
    static let demoShare = "onboarding_funnel_demo_share"
}

// MARK: - PostHogClient seam

/// Thin seam over `PostHogSDK.shared.capture(...)` so tests can substitute
/// a fake that records call shapes. Mirrors the `PurchasesProxy` pattern.
/// MainActor-isolated because callers (state machine + SwiftUI views) all
/// live on the main actor; this keeps the `[String: Any]` property dict
/// from crossing isolation boundaries.
@MainActor
protocol PostHogClient {
    func capture(_ event: String, properties: [String: Any]?)
}

/// Production conformance. Pure forwarder to `PostHogSDK.shared`. Lives
/// in this file so the rest of the codebase doesn't import PostHog
/// outside the app entrypoint + AppState.
@MainActor
struct LivePostHogClient: PostHogClient {
    func capture(_ event: String, properties: [String: Any]?) {
        PostHogSDK.shared.capture(event, properties: properties)
    }
}

// MARK: - ConversionFunnelTelemetry

/// Typed facade over `PostHogClient` for the HER-295 funnel taxonomy.
/// Each method maps 1:1 to a row in the ticket spec.
@MainActor
struct ConversionFunnelTelemetry {
    private let client: PostHogClient

    init(client: PostHogClient = LivePostHogClient()) {
        self.client = client
    }

    // MARK: View / advance / back

    func view(step: ConversionFunnelStep) {
        client.capture(ConversionFunnelEvent.view, properties: [
            "step": step.analyticsName,
        ])
    }

    func advance(step: ConversionFunnelStep, durationMs: Int) {
        client.capture(ConversionFunnelEvent.advance, properties: [
            "step": step.analyticsName,
            "duration_ms": durationMs,
        ])
    }

    func back(step: ConversionFunnelStep) {
        client.capture(ConversionFunnelEvent.back, properties: [
            "step": step.analyticsName,
        ])
    }

    // MARK: Answer payloads

    func answerGoal(_ goal: FunnelGoal) {
        client.capture(ConversionFunnelEvent.answer, properties: [
            "step": ConversionFunnelStep.goal.analyticsName,
            "value": goal.rawValue,
        ])
    }

    func answerPain(set: Set<FunnelPainPoint>) {
        client.capture(ConversionFunnelEvent.answer, properties: [
            "step": ConversionFunnelStep.painPoints.analyticsName,
            "value": set.map(\.rawValue).sorted(),
        ])
    }

    func answerSwipe(cardID: Int, agreed: Bool) {
        client.capture(ConversionFunnelEvent.answer, properties: [
            "step": ConversionFunnelStep.swipeCards.analyticsName,
            "card_id": cardID,
            "agreed": agreed,
        ])
    }

    func answerCaptureSources(_ sources: Set<FunnelCaptureSource>) {
        client.capture(ConversionFunnelEvent.answer, properties: [
            "step": ConversionFunnelStep.captureSources.analyticsName,
            "value": sources.map(\.rawValue).sorted(),
        ])
    }

    func answerDemoPick(captureID: UUID) {
        client.capture(ConversionFunnelEvent.answer, properties: [
            "step": ConversionFunnelStep.appDemo.analyticsName,
            "capture_id": captureID.uuidString,
        ])
    }

    // MARK: Funnel-completion + downstream prompts

    func completed(summary: ConversionFunnelCompletionSummary) {
        client.capture(ConversionFunnelEvent.completed, properties: [
            "total_duration_ms": summary.totalDurationMs,
            "goal": summary.goal ?? NSNull(),
            "pain_count": summary.painCount,
            "swipe_agree_count": summary.swipeAgreeCount,
            "capture_source_count": summary.captureSourceCount,
        ])
    }

    func paywallShown(paywallID: String) {
        client.capture(ConversionFunnelEvent.paywallShown, properties: [
            "paywall_id": paywallID,
        ])
    }

    func notificationPrompted(granted: Bool) {
        client.capture(ConversionFunnelEvent.notificationPrompted, properties: [
            "granted": granted,
        ])
    }

    func demoShare(captureCount: Int) {
        client.capture(ConversionFunnelEvent.demoShare, properties: [
            "capture_count": captureCount,
        ])
    }
}

// MARK: - Completion summary payload

/// Snapshot of the funnel state at completion. Built by
/// `ConversionFunnelState.completionSummary(totalDurationMs:)` so the
/// payload shape stays close to the source-of-truth selections.
struct ConversionFunnelCompletionSummary: Sendable, Equatable {
    let totalDurationMs: Int
    let goal: String?
    let painCount: Int
    let swipeAgreeCount: Int
    let captureSourceCount: Int
}

// MARK: - Step analytics names

extension ConversionFunnelStep {
    /// Stable, dashboard-friendly name. PostHog funnel charts key off
    /// these — keep them snake_case + free of UI copy churn.
    var analyticsName: String {
        switch self {
        case .welcome:              return "welcome"
        case .goal:                 return "goal"
        case .painPoints:           return "pain_points"
        case .socialProof:          return "social_proof"
        case .swipeCards:           return "swipe_cards"
        case .personalisedSolution: return "personalised_solution"
        case .comparison:           return "comparison"
        case .captureSources:       return "capture_sources"
        case .processing:           return "processing"
        case .appDemo:              return "app_demo"
        case .valueDelivery:        return "value_delivery"
        case .notificationPrime:    return "notification_prime"
        }
    }
}
