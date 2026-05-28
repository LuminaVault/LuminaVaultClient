// LuminaVaultClient/LuminaVaultClient/Features/Health/HealthDashboardCard.swift
import Charts
import SwiftUI

/// HER-118 — single metric card in the dashboard grid. 7-day sparkline
/// via Swift Charts, latest value + unit, tap navigates to detail.
struct HealthDashboardCard: View {
    let metric: HealthMetric
    let aggregate: HealthDailyResponse?
    let latestValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: metric.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(metric.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formattedLatest)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(metric.unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            sparkline
                .frame(height: 36)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title) — \(formattedLatest) \(metric.unit), last 7 days")
    }

    private var formattedLatest: String {
        if latestValue == 0 { return "–" }
        switch metric {
        case .sleep:
            let hours = latestValue / 60.0
            return String(format: "%.1f", hours)
        case .steps:
            return Int(latestValue.rounded()).formatted(.number)
        case .heartRate, .hrv:
            return Int(latestValue.rounded()).formatted(.number)
        }
    }

    @ViewBuilder
    private var sparkline: some View {
        if let aggregate, !aggregate.days.isEmpty {
            Chart(aggregate.days, id: \.date) { day in
                LineMark(
                    x: .value("Day", day.date),
                    y: .value(metric.title, day.value),
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.tint)
                AreaMark(
                    x: .value("Day", day.date),
                    y: .value(metric.title, day.value),
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.tint.opacity(0.12))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
        } else {
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
        }
    }
}
