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
    /// HER-248 — used to build the insight detail screen pushed from the
    /// Patterns section.
    let httpClient: BaseHTTPClient

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                rangePicker
                summaryHeader
                content
                patternsSection
            }
            .padding(20)
        }
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.large)
        .task { await vm.load() }
    }

    private var rangePicker: some View {
        Picker("Range", selection: Binding(
            get: { vm.range },
            set: { newValue in Task { await vm.setRange(newValue) } },
        )) {
            ForEach(AnalyticsRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var summaryHeader: some View {
        if let summary = vm.summary {
            HStack(spacing: 12) {
                summaryStat("Sessions", "\(summary.sessionsCount)")
                summaryStat("Tokens in", summary.llmTokensIn.formatted(.number))
                summaryStat("Cost", costString(summary.estimatedCostCents))
            }
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

    private func costString(_ cents: Int) -> String {
        (Double(cents) / 100.0).formatted(.currency(code: "USD"))
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
            Text("PATTERNS")
                .font(.caption2.weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(.secondary)

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
