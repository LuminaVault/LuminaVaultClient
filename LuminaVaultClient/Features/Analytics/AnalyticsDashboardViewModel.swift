import Foundation
import LuminaVaultShared

@Observable
@MainActor
final class AnalyticsDashboardViewModel {
    enum LoadState: Equatable { case loading, loaded, failed(String) }

    var state: LoadState = .loading
    var range: AnalyticsRange = .month
    var series: [TrendSeriesUIModel] = []
    var overview: AnalyticsOverviewResponse?
    var modelEffectiveness: [ModelEffectivenessDTO] = []
    var patternInsights: [InsightDTO] = []

    private let analytics: any UsageIntelligenceClientProtocol
    private let insights: any InsightsClientProtocol

    init(analytics: any UsageIntelligenceClientProtocol, insights: any InsightsClientProtocol) {
        self.analytics = analytics
        self.insights = insights
    }

    func setRange(_ range: AnalyticsRange) async {
        guard range != self.range else { return }
        self.range = range
        try? await analytics.record(.init(name: .rangeChanged, source: .ios, range: range))
        await load()
    }

    func load() async {
        state = .loading
        async let models = try? analytics.models(range: range)
        async let insights = loadInsights()
        do {
            let response = try await analytics.overview(range: range)
            overview = response
            series = Self.makeSeries(response.daily)
            modelEffectiveness = (await models)?.models ?? []
            patternInsights = await insights
            state = .loaded
            try? await analytics.record(.init(name: .dashboardViewed, source: .ios, range: range))
        } catch {
            state = .failed(error.localizedDescription)
            modelEffectiveness = (await models)?.models ?? []
            patternInsights = await insights
        }
    }

    func setRecommendation(_ recommendation: AnalyticsRecommendationDTO,
                           disposition: AnalyticsRecommendationDisposition) async
    {
        do {
            try await analytics.updateRecommendation(.init(
                recommendationId: recommendation.id,
                disposition: disposition
            ))
            overview = overview.map { current in
                AnalyticsOverviewResponse(
                    scope: current.scope, vaultId: current.vaultId, range: current.range,
                    periodStart: current.periodStart, periodEnd: current.periodEnd,
                    summary: current.summary, daily: current.daily, memoryHealth: current.memoryHealth,
                    recommendations: current.recommendations.filter { $0.id != recommendation.id }
                )
            }
            let event: AnalyticsClientEventName = disposition == .dismiss
                ? .recommendationDismissed : .recommendationSnoozed
            try? await analytics.record(.init(name: event, source: .ios,
                                              recommendationId: recommendation.id))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func opened(_ recommendation: AnalyticsRecommendationDTO) async {
        try? await analytics.record(.init(name: .recommendationOpened, source: .ios,
                                          recommendationId: recommendation.id))
    }

    private nonisolated func loadInsights() async -> [InsightDTO] {
        async let patterns = try? insights.list(section: .patterns, limit: 5)
        async let contradictions = try? insights.list(section: .contradictions, limit: 5)
        let combined = (await patterns?.insights ?? []) + (await contradictions?.insights ?? [])
        return combined.sorted { $0.createdAt > $1.createdAt }
    }

    private static func makeSeries(_ daily: [AnalyticsDailyPointDTO]) -> [TrendSeriesUIModel] {
        let definitions: [(String, String, String, String, (AnalyticsDailyPointDTO) -> Double)] = [
            ("usage.tokens", "Tokens", "cpu", "tok", { Double($0.tokens) }),
            ("knowledge.captures", "Memories captured", "square.and.arrow.down", "items", { Double($0.captures) }),
            ("knowledge.retrievals", "Memory retrievals", "magnifyingglass", "hits", { Double($0.retrievals) }),
            ("usage.requests", "AI requests", "sparkles", "runs", { Double($0.aiRequests) }),
        ]
        return definitions.map { id, title, image, unit, value in
            let points = daily.map { TrendPointUIModel(date: $0.date, value: value($0)) }
            return TrendSeriesUIModel(id: id, title: title, systemImage: image, unit: unit,
                                      points: points, latest: points.last?.value ?? 0)
        }
    }
}
