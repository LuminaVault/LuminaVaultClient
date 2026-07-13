import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

@MainActor
final class AnalyticsDashboardViewModelTests: XCTestCase {
    func testLoadBuildsEveryUsageSeriesAndRecordsDashboardView() async {
        let recommendation = Self.recommendation
        let analytics = AnalyticsClientStub(overview: Self.overview(recommendations: [recommendation]))
        let viewModel = AnalyticsDashboardViewModel(
            analytics: analytics,
            insights: InsightsClientStub()
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.series.map(\.id), [
            "usage.tokens",
            "knowledge.captures",
            "knowledge.retrievals",
            "usage.requests",
        ])
        XCTAssertEqual(viewModel.overview?.memoryHealth.score, 74)
        let events = await analytics.recordedEvents()
        XCTAssertEqual(events, [.dashboardViewed])
        XCTAssertEqual(viewModel.state, .loaded)
    }

    func testSnoozingRecommendationRemovesItAndRecordsDisposition() async {
        let recommendation = Self.recommendation
        let analytics = AnalyticsClientStub(overview: Self.overview(recommendations: [recommendation]))
        let viewModel = AnalyticsDashboardViewModel(
            analytics: analytics,
            insights: InsightsClientStub()
        )
        await viewModel.load()

        await viewModel.setRecommendation(recommendation, disposition: .snooze7)

        XCTAssertEqual(viewModel.overview?.recommendations, [])
        let disposition = await analytics.lastDisposition()
        let events = await analytics.recordedEvents()
        XCTAssertEqual(disposition, .snooze7)
        XCTAssertTrue(events.contains(.recommendationSnoozed))
    }

    func testRecommendationDestinationAllowsOnlySupportedInternalRoutes() {
        XCTAssertEqual(
            AnalyticsRecommendationDestination(deepLink: "/memories?filter=unused"),
            .memory(.unused)
        )
        XCTAssertEqual(
            AnalyticsRecommendationDestination(deepLink: "/memories?reviewState=pending"),
            .memory(.pending)
        )
        XCTAssertEqual(
            AnalyticsRecommendationDestination(deepLink: "/analytics#models"),
            .models
        )
        XCTAssertNil(AnalyticsRecommendationDestination(deepLink: "https://attacker.example/memories"))
        XCTAssertNil(AnalyticsRecommendationDestination(deepLink: "/settings"))
    }

    func testRatingModelRecordsContentFreeFeedbackOncePerScreen() async {
        let model = ModelEffectivenessDTO(
            provider: "openai",
            model: "gpt-test",
            requests: 2,
            successRate: 1,
            fallbackRate: 0,
            averageLatencyMs: 100,
            p95LatencyMs: 120,
            tokens: 20,
            estimatedCostUsdMicros: 50
        )
        let analytics = AnalyticsClientStub(
            overview: Self.overview(recommendations: []),
            models: [model]
        )
        let viewModel = AnalyticsDashboardViewModel(
            analytics: analytics,
            insights: InsightsClientStub()
        )

        await viewModel.rate(model, rating: .positive)
        await viewModel.rate(model, rating: .negative)

        let feedback = await analytics.recordedFeedback()
        XCTAssertEqual(feedback.map(\.rating), [.positive])
        XCTAssertEqual(feedback.first?.provider, "openai")
        XCTAssertEqual(feedback.first?.model, "gpt-test")
    }

    private static let recommendation = AnalyticsRecommendationDTO(
        id: "memory-review-overdue",
        title: "Review older memories",
        detail: "Two memories are ready for review.",
        severity: .important,
        actionTitle: "Open review queue",
        deepLink: "/memories?filter=review-overdue"
    )

    private static func overview(
        recommendations: [AnalyticsRecommendationDTO]
    ) -> AnalyticsOverviewResponse {
        AnalyticsOverviewResponse(
            scope: .personal,
            vaultId: UUID(),
            range: .month,
            periodStart: .now.addingTimeInterval(-29 * 24 * 60 * 60),
            periodEnd: .now,
            summary: .init(sessions: 2, aiRequests: 4, tokensIn: 10, tokensOut: 20,
                           captures: 3, retrievals: 5, estimatedCostUsdMicros: 100),
            daily: [
                .init(date: .now, sessions: 2, aiRequests: 4, tokens: 30, captures: 3,
                      retrievals: 5, estimatedCostUsdMicros: 100),
            ],
            memoryHealth: .init(
                score: 74,
                totalMemories: 10,
                staleCount: 2,
                neverRetrievedCount: 1,
                unorganizedCount: 1,
                pendingReviewCount: 0,
                components: []
            ),
            recommendations: recommendations
        )
    }
}

private actor AnalyticsClientStub: UsageIntelligenceClientProtocol {
    let overviewValue: AnalyticsOverviewResponse
    let modelValues: [ModelEffectivenessDTO]
    var events: [AnalyticsClientEventName] = []
    var feedback: [ModelFeedbackRequest] = []
    var disposition: AnalyticsRecommendationDisposition?

    init(overview: AnalyticsOverviewResponse, models: [ModelEffectivenessDTO] = []) {
        overviewValue = overview
        modelValues = models
    }

    func overview(range _: AnalyticsRange) async throws -> AnalyticsOverviewResponse { overviewValue }

    func models(range: AnalyticsRange) async throws -> ModelEffectivenessResponse {
        ModelEffectivenessResponse(range: range, models: modelValues)
    }

    func record(_ event: AnalyticsEventRequest) async throws {
        events.append(event.name)
    }

    func recordModelFeedback(_ value: ModelFeedbackRequest) async throws {
        feedback.append(value)
    }

    func updateRecommendation(_ request: AnalyticsRecommendationStateRequest) async throws {
        disposition = request.disposition
    }

    func recordedEvents() -> [AnalyticsClientEventName] { events }
    func recordedFeedback() -> [ModelFeedbackRequest] { feedback }
    func lastDisposition() -> AnalyticsRecommendationDisposition? { disposition }
}

private actor InsightsClientStub: InsightsClientProtocol {
    func list(section _: InsightSection?, limit _: Int?) async throws -> InsightListResponse {
        InsightListResponse(insights: [])
    }

    func dismiss(id _: UUID) async throws {}
}
