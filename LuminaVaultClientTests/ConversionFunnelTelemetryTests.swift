// LuminaVaultClient/LuminaVaultClientTests/ConversionFunnelTelemetryTests.swift
//
// HER-295 — covers the conversion-funnel telemetry wrapper end to end:
// the typed facade emits the right event names + property shapes, and
// `ConversionFunnelState` fires `view` / `advance` / `back` / `answer`
// at the right moments with a deterministic clock.

import XCTest
@testable import LuminaVaultClient

@MainActor
final class ConversionFunnelTelemetryTests: XCTestCase {

    // MARK: - Fake PostHog client

    /// In-memory recorder. Mirrors the `MockPurchasesProxy` pattern: the
    /// production wrapper code is exercised with a fake transport so the
    /// PostHog SDK never has to spin up in the test bundle.
    final class FakePostHogClient: PostHogClient, @unchecked Sendable {
        struct Call: Equatable {
            let event: String
            let properties: [String: AnyHashableValue]
        }

        private(set) var calls: [Call] = []

        func capture(_ event: String, properties: [String: Any]?) {
            let normalized = (properties ?? [:]).mapValues(AnyHashableValue.from(_:))
            calls.append(Call(event: event, properties: normalized))
        }

        func reset() { calls = [] }

        var events: [String] { calls.map(\.event) }

        func propertiesOf(_ event: String) -> [String: AnyHashableValue]? {
            calls.first(where: { $0.event == event })?.properties
        }
    }

    /// Type-erased value that PostHog properties can take, narrowed to
    /// shapes we actually emit. `AnyHashable` would also work — this
    /// variant gives clearer failure messages on assert.
    enum AnyHashableValue: Hashable, Equatable {
        case string(String)
        case int(Int)
        case bool(Bool)
        case stringArray([String])
        case null

        static func from(_ value: Any) -> AnyHashableValue {
            if value is NSNull { return .null }
            if let v = value as? String { return .string(v) }
            if let v = value as? Bool { return .bool(v) }
            if let v = value as? Int { return .int(v) }
            if let v = value as? [String] { return .stringArray(v) }
            return .string(String(describing: value))
        }
    }

    // MARK: - Direct wrapper coverage

    func testViewEmitsStepName() {
        let fake = FakePostHogClient()
        let tel = ConversionFunnelTelemetry(client: fake)

        tel.view(step: .goal)

        XCTAssertEqual(fake.events, ["onboarding_funnel_view"])
        XCTAssertEqual(fake.propertiesOf("onboarding_funnel_view"), ["step": .string("goal")])
    }

    func testAdvanceEmitsStepAndDurationMs() {
        let fake = FakePostHogClient()
        let tel = ConversionFunnelTelemetry(client: fake)

        tel.advance(step: .painPoints, durationMs: 4_321)

        XCTAssertEqual(fake.events, ["onboarding_funnel_advance"])
        XCTAssertEqual(fake.propertiesOf("onboarding_funnel_advance"),
                       ["step": .string("pain_points"), "duration_ms": .int(4_321)])
    }

    func testBackEmitsStepName() {
        let fake = FakePostHogClient()
        let tel = ConversionFunnelTelemetry(client: fake)

        tel.back(step: .swipeCards)

        XCTAssertEqual(fake.events, ["onboarding_funnel_back"])
        XCTAssertEqual(fake.propertiesOf("onboarding_funnel_back"), ["step": .string("swipe_cards")])
    }

    func testAnswerGoal() {
        let fake = FakePostHogClient()
        let tel = ConversionFunnelTelemetry(client: fake)

        tel.answerGoal(.knowledgeBase)

        XCTAssertEqual(fake.events, ["onboarding_funnel_answer"])
        XCTAssertEqual(fake.propertiesOf("onboarding_funnel_answer"),
                       ["step": .string("goal"), "value": .string("knowledgeBase")])
    }

    func testAnswerPainEmitsSortedStableArray() {
        let fake = FakePostHogClient()
        let tel = ConversionFunnelTelemetry(client: fake)

        // Insertion order should not affect serialized property.
        tel.answerPain(set: [.scatteredNotes, .cloudPrivacy, .genericReplies])

        let props = fake.propertiesOf("onboarding_funnel_answer")
        XCTAssertEqual(props?["step"], .string("pain_points"))
        XCTAssertEqual(props?["value"], .stringArray(
            ["cloudPrivacy", "genericReplies", "scatteredNotes"].sorted()
        ))
    }

    func testAnswerSwipe() {
        let fake = FakePostHogClient()
        let tel = ConversionFunnelTelemetry(client: fake)

        tel.answerSwipe(cardID: 2, agreed: true)

        XCTAssertEqual(fake.propertiesOf("onboarding_funnel_answer"),
                       [
                           "step": .string("swipe_cards"),
                           "card_id": .int(2),
                           "agreed": .bool(true),
                       ])
    }

    func testAnswerCaptureSourcesSorted() {
        let fake = FakePostHogClient()
        let tel = ConversionFunnelTelemetry(client: fake)

        tel.answerCaptureSources([.voiceMemos, .photos])

        let props = fake.propertiesOf("onboarding_funnel_answer")
        XCTAssertEqual(props?["step"], .string("capture_sources"))
        XCTAssertEqual(props?["value"], .stringArray(["photos", "voiceMemos"]))
    }

    func testAnswerDemoPickEmitsUUIDString() {
        let fake = FakePostHogClient()
        let tel = ConversionFunnelTelemetry(client: fake)
        let id = UUID()

        tel.answerDemoPick(captureID: id)

        XCTAssertEqual(fake.propertiesOf("onboarding_funnel_answer"),
                       ["step": .string("app_demo"), "capture_id": .string(id.uuidString)])
    }

    func testCompletedEmitsAggregateSummary() {
        let fake = FakePostHogClient()
        let tel = ConversionFunnelTelemetry(client: fake)

        tel.completed(summary: ConversionFunnelCompletionSummary(
            totalDurationMs: 60_000,
            goal: "knowledgeBase",
            painCount: 2,
            swipeAgreeCount: 3,
            captureSourceCount: 4
        ))

        XCTAssertEqual(fake.propertiesOf("onboarding_funnel_completed"), [
            "total_duration_ms": .int(60_000),
            "goal": .string("knowledgeBase"),
            "pain_count": .int(2),
            "swipe_agree_count": .int(3),
            "capture_source_count": .int(4),
        ])
    }

    func testCompletedWithNilGoalEmitsNull() {
        let fake = FakePostHogClient()
        let tel = ConversionFunnelTelemetry(client: fake)

        tel.completed(summary: ConversionFunnelCompletionSummary(
            totalDurationMs: 1_000,
            goal: nil,
            painCount: 0,
            swipeAgreeCount: 0,
            captureSourceCount: 0
        ))

        XCTAssertEqual(fake.propertiesOf("onboarding_funnel_completed")?["goal"], .null)
    }

    func testPaywallShown() {
        let fake = FakePostHogClient()
        let tel = ConversionFunnelTelemetry(client: fake)

        tel.paywallShown(paywallID: "default")

        XCTAssertEqual(fake.events, ["onboarding_funnel_paywall_shown"])
        XCTAssertEqual(fake.propertiesOf("onboarding_funnel_paywall_shown"),
                       ["paywall_id": .string("default")])
    }

    func testNotificationPromptedGranted() {
        let fake = FakePostHogClient()
        let tel = ConversionFunnelTelemetry(client: fake)

        tel.notificationPrompted(granted: true)

        XCTAssertEqual(fake.propertiesOf("onboarding_funnel_notification_prompted"),
                       ["granted": .bool(true)])
    }

    func testNotificationPromptedDenied() {
        let fake = FakePostHogClient()
        let tel = ConversionFunnelTelemetry(client: fake)

        tel.notificationPrompted(granted: false)

        XCTAssertEqual(fake.propertiesOf("onboarding_funnel_notification_prompted"),
                       ["granted": .bool(false)])
    }

    func testDemoShare() {
        let fake = FakePostHogClient()
        let tel = ConversionFunnelTelemetry(client: fake)

        tel.demoShare(captureCount: 3)

        XCTAssertEqual(fake.propertiesOf("onboarding_funnel_demo_share"),
                       ["capture_count": .int(3)])
    }

    // MARK: - State machine integration

    func testStateInitFiresWelcomeView() {
        let fake = FakePostHogClient()
        let tel = ConversionFunnelTelemetry(client: fake)

        _ = ConversionFunnelState(telemetry: tel, now: { Date(timeIntervalSince1970: 0) })

        XCTAssertEqual(fake.events, ["onboarding_funnel_view"])
        XCTAssertEqual(fake.propertiesOf("onboarding_funnel_view"), ["step": .string("welcome")])
    }

    func testStateAdvanceFiresAdvanceThenView() {
        let fake = FakePostHogClient()
        let tel = ConversionFunnelTelemetry(client: fake)
        var clock = Date(timeIntervalSince1970: 0)
        let state = ConversionFunnelState(telemetry: tel, now: { clock })
        fake.reset()  // discard the welcome view fired in init

        // 2.5 seconds on the welcome screen, then advance.
        clock = Date(timeIntervalSince1970: 2.5)
        state.advance()

        // First event is advance(welcome, duration_ms=2500).
        XCTAssertEqual(fake.calls.count, 2)
        XCTAssertEqual(fake.calls[0].event, "onboarding_funnel_advance")
        XCTAssertEqual(fake.calls[0].properties,
                       ["step": .string("welcome"), "duration_ms": .int(2_500)])
        // Then view(goal).
        XCTAssertEqual(fake.calls[1].event, "onboarding_funnel_view")
        XCTAssertEqual(fake.calls[1].properties, ["step": .string("goal")])
    }

    func testStateGoBackFiresBackThenView() {
        let fake = FakePostHogClient()
        let tel = ConversionFunnelTelemetry(client: fake)
        let state = ConversionFunnelState(telemetry: tel, now: { Date(timeIntervalSince1970: 0) })

        state.advance()  // welcome → goal
        fake.reset()

        state.goBack()  // goal → welcome

        XCTAssertEqual(fake.calls.count, 2)
        XCTAssertEqual(fake.calls[0].event, "onboarding_funnel_back")
        XCTAssertEqual(fake.calls[0].properties, ["step": .string("goal")])
        XCTAssertEqual(fake.calls[1].event, "onboarding_funnel_view")
        XCTAssertEqual(fake.calls[1].properties, ["step": .string("welcome")])
    }

    func testStateMutatorsFireAnswerEvents() {
        let fake = FakePostHogClient()
        let tel = ConversionFunnelTelemetry(client: fake)
        let state = ConversionFunnelState(telemetry: tel, now: { Date(timeIntervalSince1970: 0) })
        fake.reset()

        state.selectGoal(.captureIdeas)
        state.togglePain(.scatteredNotes)
        state.recordSwipe(cardID: 1, agreed: true)
        state.toggleCaptureSource(.photos)
        state.recordDemoPick(captureID: FunnelSampleCapture.all[0].id)

        // Every mutator emits exactly one `answer` event.
        XCTAssertEqual(fake.events, Array(repeating: "onboarding_funnel_answer", count: 5))
        XCTAssertEqual(fake.calls[0].properties["value"], .string("captureIdeas"))
        XCTAssertEqual(fake.calls[1].properties["value"], .stringArray(["scatteredNotes"]))
        XCTAssertEqual(fake.calls[2].properties["card_id"], .int(1))
        XCTAssertEqual(fake.calls[2].properties["agreed"], .bool(true))
        XCTAssertEqual(fake.calls[3].properties["value"], .stringArray(["photos"]))
        XCTAssertEqual(fake.calls[4].properties["step"], .string("app_demo"))
    }

    func testCompletionSummaryAggregatesAnswers() {
        let fake = FakePostHogClient()
        let tel = ConversionFunnelTelemetry(client: fake)
        var clock = Date(timeIntervalSince1970: 0)
        let state = ConversionFunnelState(telemetry: tel, now: { clock })

        state.selectGoal(.knowledgeBase)
        state.togglePain(.scatteredNotes)
        state.togglePain(.cloudPrivacy)
        state.recordSwipe(cardID: 0, agreed: true)
        state.recordSwipe(cardID: 1, agreed: true)
        state.recordSwipe(cardID: 2, agreed: false)
        state.toggleCaptureSource(.photos)

        clock = Date(timeIntervalSince1970: 12.345)
        let summary = state.completionSummary()
        XCTAssertEqual(summary.totalDurationMs, 12_345)
        XCTAssertEqual(summary.goal, "knowledgeBase")
        XCTAssertEqual(summary.painCount, 2)
        XCTAssertEqual(summary.swipeAgreeCount, 2)
        XCTAssertEqual(summary.captureSourceCount, 1)
    }
}
