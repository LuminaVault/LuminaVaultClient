// LuminaVaultClient/LuminaVaultClient/Features/Analytics/AnalyticsDashboardView.swift
//
// HER-56 — Deep Analytics & Patterns dashboard. Renders live trend charts
// for Health, token usage, and achievement signals over a selectable range,
// plus a usage-summary header. HER-248 — the Patterns section now lists
// live pattern/contradiction insights, each tappable to a detail screen.
//
// The screen is an inset-grouped `List`: the sections, their headers, their
// row insets and their background all come from the system, so nothing here
// hand-rolls a card. The range lives in the navigation bar (`InsightsTabView`)
// rather than in the content.

import LuminaVaultShared
import SwiftUI

struct AnalyticsDashboardView: View {
    let vm: AnalyticsDashboardViewModel
    /// HER-248 — used to build the insight detail screen pushed from the
    /// Patterns section.
    let httpClient: BaseHTTPClient
    let onOpenRecommendation: (String) -> Void

    var body: some View {
        List {
            memoryHealthSection
            usageSection
            recommendationsSection
            trendsSection
            modelsSection
            patternsSection
        }
        .listStyle(.insetGrouped)
        .task { await vm.load() }
    }

    // MARK: - Memory health

    @ViewBuilder
    private var memoryHealthSection: some View {
        if let health = vm.overview?.memoryHealth {
            Section("Memory health") {
                LabeledContent("Score") {
                    Text("\(health.score) / 100")
                        .monospacedDigit()
                }
                .accessibilityLabel("Memory health \(health.score) out of 100")

                ForEach(health.components, id: \.key) { component in
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent(component.title) {
                            Text("\(component.score)%")
                                .monospacedDigit()
                        }
                        ProgressView(value: Double(component.score), total: 100)
                    }
                    .accessibilityElement(children: .combine)
                }

                DisclosureGroup("How this score works") {
                    Text("Freshness contributes 35% and decays with a 30-day half-life. Engagement contributes 25% from useful access and retrieval. Organization contributes 20% from tags and filing. Review readiness contributes 20% from recently reviewed, approved knowledge.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Usage

    @ViewBuilder
    private var usageSection: some View {
        if let summary = vm.overview?.summary {
            // `Text(_:format:)` rather than a pre-formatted string: the
            // formatter then follows the environment locale, which is what
            // the rest of the row does and what keeps a snapshot from
            // reading the host's regional settings.
            Section("Usage") {
                LabeledContent("AI requests") {
                    Text(summary.aiRequests, format: .number)
                }
                LabeledContent("Tokens") {
                    Text(summary.tokensIn + summary.tokensOut, format: .number)
                }
                LabeledContent("Cost") {
                    Text(dollars(summary.estimatedCostUsdMicros), format: .currency(code: "USD"))
                }
            }
        }
    }

    private func dollars(_ micros: Int64) -> Double {
        Double(micros) / 1_000_000.0
    }

    // MARK: - Recommended

    @ViewBuilder
    private var recommendationsSection: some View {
        if let recommendations = vm.overview?.recommendations, !recommendations.isEmpty {
            Section("Recommended") {
                ForEach(recommendations) { recommendation in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(recommendation.title)
                            .font(.headline)
                        Text(recommendation.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button(recommendation.actionTitle) {
                                Task { await vm.opened(recommendation) }
                                onOpenRecommendation(recommendation.deepLink)
                            }
                            .font(.subheadline.weight(.semibold))
                            Spacer()
                            Menu("More", systemImage: "ellipsis") {
                                Button("Snooze 7 days") {
                                    Task { await vm.setRecommendation(recommendation, disposition: .snooze7) }
                                }
                                Button("Snooze 30 days") {
                                    Task { await vm.setRecommendation(recommendation, disposition: .snooze30) }
                                }
                                Button("Dismiss", role: .destructive) {
                                    Task { await vm.setRecommendation(recommendation, disposition: .dismiss) }
                                }
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Trends

    @ViewBuilder
    private var trendsSection: some View {
        Section("Trends") {
            switch vm.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            case .failed(let message):
                ContentUnavailableView(
                    "Couldn't load analytics",
                    systemImage: "chart.xyaxis.line",
                    description: Text(message),
                )
            case .loaded where vm.series.isEmpty:
                ContentUnavailableView(
                    "No trends yet",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Connect Health and keep using Lumina to see trends here."),
                )
            case .loaded:
                ForEach(vm.series) { series in
                    TrendChartCard(series: series)
                }
            }
        }
    }

    // MARK: - Models

    @ViewBuilder
    private var modelsSection: some View {
        if !vm.modelEffectiveness.isEmpty {
            Section("Models") {
                ForEach(vm.modelEffectiveness.prefix(4)) { model in
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(model.successRate, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                            Text("\(model.averageLatencyMs) ms")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Text(model.model)
                            .lineLimit(1)
                        Text(model.provider)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - Patterns

    @ViewBuilder
    private var patternsSection: some View {
        Section("Patterns") {
            if vm.patternInsights.isEmpty {
                Text("Lumina will surface correlations and contradictions across these signals here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.patternInsights) { insight in
                    NavigationLink {
                        InsightDetailView.make(insight: insight, httpClient: httpClient)
                    } label: {
                        insightRow(insight)
                    }
                }
            }
        }
    }

    private func insightRow(_ insight: InsightDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(insight.section.displayLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Text(insight.headline)
                .font(.headline)
            Text(insight.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }
}
