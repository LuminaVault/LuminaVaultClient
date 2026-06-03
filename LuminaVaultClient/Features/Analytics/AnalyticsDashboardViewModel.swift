// LuminaVaultClient/LuminaVaultClient/Features/Analytics/AnalyticsDashboardViewModel.swift
//
// HER-56 — backs the Deep Analytics & Patterns dashboard. Fans out the
// existing read clients (Health daily, billing usage, achievements, usage
// summary) concurrently and maps the shared DTOs into `TrendSeriesUIModel`s.
// No new endpoints: every signal is already served at LuminaVaultShared
// v0.62.0. Per-source failures degrade to an omitted series rather than
// failing the whole screen — partial data is still useful here.

import Foundation
import LuminaVaultShared

@Observable
@MainActor
final class AnalyticsDashboardViewModel {
    enum LoadState: Equatable { case loading, loaded, failed(String) }

    var state: LoadState = .loading
    var range: AnalyticsRange = .month
    var series: [TrendSeriesUIModel] = []
    var summary: UsageSummaryResponse?
    /// HER-248 — narrative findings (patterns + contradictions) shown in
    /// the Patterns section beneath the charts.
    var patternInsights: [InsightDTO] = []

    private let health: any HealthDashboardEndpointsExecutor
    private let analytics: any AnalyticsClientProtocol
    private let achievements: any AchievementsClientProtocol
    private let billing: any BillingClientProtocol
    private let insights: any InsightsClientProtocol

    init(
        health: any HealthDashboardEndpointsExecutor,
        analytics: any AnalyticsClientProtocol,
        achievements: any AchievementsClientProtocol,
        billing: any BillingClientProtocol,
        insights: any InsightsClientProtocol,
    ) {
        self.health = health
        self.analytics = analytics
        self.achievements = achievements
        self.billing = billing
        self.insights = insights
    }

    func setRange(_ range: AnalyticsRange) async {
        guard range != self.range else { return }
        self.range = range
        await load()
    }

    func load() async {
        state = .loading
        let days = range.days

        // Independent sources fan out concurrently.
        async let healthSeries = loadHealthSeries(days: days)
        async let tokenSeries = loadTokenSeries()
        async let achievementSeries = loadAchievementSeries(days: days)
        async let summaryResult = loadSummary()
        async let insightsResult = loadInsights()

        var collected = await healthSeries
        if let tokens = await tokenSeries { collected.append(tokens) }
        if let unlocks = await achievementSeries { collected.append(unlocks) }
        summary = await summaryResult
        patternInsights = await insightsResult

        series = collected
        state = .loaded
    }

    // MARK: - Source mappers (nonisolated: read only immutable injected clients)

    private nonisolated func loadSummary() async -> UsageSummaryResponse? {
        try? await analytics.usageSummary()
    }

    /// HER-248 — patterns + contradictions, newest first. Two list calls
    /// (the feed filters by a single section); per-call failures degrade
    /// to an empty Patterns section rather than failing the dashboard.
    private nonisolated func loadInsights() async -> [InsightDTO] {
        async let patterns = try? insights.list(section: .patterns, limit: 5)
        async let contradictions = try? insights.list(section: .contradictions, limit: 5)
        let combined = (await patterns?.insights ?? []) + (await contradictions?.insights ?? [])
        return combined.sorted { $0.createdAt > $1.createdAt }
    }

    private nonisolated func loadHealthSeries(days: Int) async -> [TrendSeriesUIModel] {
        await withTaskGroup(of: TrendSeriesUIModel?.self) { group in
            for metric in HealthMetric.allCases {
                group.addTask { [health] in
                    guard let response = try? await health.daily(
                        type: metric.serverType,
                        days: days,
                    ) else { return nil }

                    let points = response.days.map {
                        TrendPointUIModel(date: $0.date, value: $0.value)
                    }
                    let latest = points.last(where: { $0.value != 0 })?.value ?? 0
                    return TrendSeriesUIModel(
                        id: "health.\(metric.rawValue)",
                        title: metric.title,
                        systemImage: metric.systemImage,
                        unit: metric.unit,
                        points: points,
                        latest: latest,
                    )
                }
            }
            var result: [TrendSeriesUIModel] = []
            for await series in group {
                if let series { result.append(series) }
            }
            return result.sorted { $0.id < $1.id }
        }
    }

    private nonisolated func loadTokenSeries() async -> TrendSeriesUIModel? {
        guard let usage = try? await billing.fetchMeUsage() else { return nil }
        let points = usage.daily
            .sorted { $0.day < $1.day }
            .map { TrendPointUIModel(date: $0.day, value: Double($0.tokensIn + $0.tokensOut)) }
        guard !points.isEmpty else { return nil }
        return TrendSeriesUIModel(
            id: "usage.tokens",
            title: "Tokens",
            systemImage: "cpu",
            unit: "tok",
            points: points,
            latest: points.last?.value ?? 0,
        )
    }

    private nonisolated func loadAchievementSeries(days: Int) async -> TrendSeriesUIModel? {
        guard let recent = try? await achievements.recent(limit: 50) else { return nil }
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let unlocks = recent.unlocks.filter { $0.unlockedAt >= cutoff }
        guard !unlocks.isEmpty else { return nil }

        // One point per day = badges unlocked that day.
        let grouped = Dictionary(grouping: unlocks) { calendar.startOfDay(for: $0.unlockedAt) }
        let points = grouped
            .map { TrendPointUIModel(date: $0.key, value: Double($0.value.count)) }
            .sorted { $0.date < $1.date }
        return TrendSeriesUIModel(
            id: "achievements.unlocks",
            title: "Unlocks",
            systemImage: "trophy.fill",
            unit: "badges",
            points: points,
            latest: Double(unlocks.count),
        )
    }
}
