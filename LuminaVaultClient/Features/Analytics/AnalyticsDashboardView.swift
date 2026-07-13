// LuminaVaultClient/LuminaVaultClient/Features/Analytics/AnalyticsDashboardView.swift
//
// HER-56 — Deep Analytics & Patterns dashboard. Renders live trend charts
// for Health, token usage, and achievement signals over a selectable range,
// plus a usage-summary header. HER-248 — the Patterns section now lists
// live pattern/contradiction insights, each tappable to a detail screen.

import LuminaVaultShared
import SwiftUI

struct AnalyticsDashboardView: View {
    let vm: AnalyticsDashboardViewModel
    @State private var selectedRange: AnalyticsRange = .month
    /// HER-248 — used to build the insight detail screen pushed from the
    /// Patterns section.
    let httpClient: BaseHTTPClient
    let onOpenRecommendation: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                rangePicker
                memoryHealth
                summaryHeader
                recommendationsSection
                content
                modelsSection
                patternsSection
            }
            .padding(20)
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.large)
        .task { await vm.load() }
    }

    private var rangePicker: some View {
        Picker("Range", selection: $selectedRange) {
            ForEach(AnalyticsRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: selectedRange) { _, newValue in
            Task { await vm.setRange(newValue) }
        }
    }

    @ViewBuilder
    private var summaryHeader: some View {
        if let summary = vm.overview?.summary {
            HStack(spacing: 12) {
                summaryStat("AI requests", "\(summary.aiRequests)")
                summaryStat("Tokens", (summary.tokensIn + summary.tokensOut).formatted(.number))
                summaryStat("Cost", costString(summary.estimatedCostUsdMicros))
            }
        }
    }

    @ViewBuilder
    private var memoryHealth: some View {
        if let health = vm.overview?.memoryHealth {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Memory health")
                        .font(.headline)
                    Spacer()
                    Text("\(health.score)")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Text("/ 100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(health.components, id: \.key) { component in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(component.title).font(.caption)
                            Spacer()
                            Text("\(component.score)%").font(.caption.monospacedDigit())
                        }
                        ProgressView(value: Double(component.score), total: 100)
                    }
                    .accessibilityElement(children: .combine)
                }
                DisclosureGroup("How this score works") {
                    Text("Freshness contributes 35% and decays with a 30-day half-life. Engagement contributes 25% from useful access and retrieval. Organization contributes 20% from tags and filing. Review readiness contributes 20% from recently reviewed, approved knowledge.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .font(.footnote)
            }
            .padding(16)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Memory health \(health.score) out of 100")
        }
    }

    private func summaryStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func costString(_ micros: Int64) -> String {
        (Double(micros) / 1_000_000.0).formatted(.currency(code: "USD"))
    }

    @ViewBuilder
    private var recommendationsSection: some View {
        if let recommendations = vm.overview?.recommendations, !recommendations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("RECOMMENDED")
                ForEach(recommendations) { recommendation in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(recommendation.title).font(.subheadline.weight(.semibold))
                        Text(recommendation.detail).font(.footnote).foregroundStyle(.secondary)
                        HStack {
                            Button(recommendation.actionTitle) {
                                Task { await vm.opened(recommendation) }
                                onOpenRecommendation(recommendation.deepLink)
                            }
                            .font(.caption.weight(.semibold))
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
                            .font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
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
            LazyVStack(spacing: 16) {
                ForEach(vm.series) { series in
                    TrendChartCard(series: series)
                }
            }
        }
    }

    @ViewBuilder
    private var patternsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("PATTERNS")

            if vm.patternInsights.isEmpty {
                Text("Lumina will surface correlations and contradictions across these signals here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(vm.patternInsights) { insight in
                    NavigationLink {
                        InsightDetailView.make(insight: insight, httpClient: httpClient)
                    } label: {
                        insightCard(insight)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var modelsSection: some View {
        if !vm.modelEffectiveness.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("MODEL EFFECTIVENESS")
                ForEach(vm.modelEffectiveness.prefix(4)) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.model).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(model.provider).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(model.successRate, format: .percent.precision(.fractionLength(0)))
                                .font(.subheadline.monospacedDigit())
                            Text("\(model.averageLatencyMs) ms")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.heavy))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }

    private func insightCard(_ insight: InsightDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(insight.section.displayLabel.uppercased())
                .font(.caption2.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(.tint)
            Text(insight.headline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(insight.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}
