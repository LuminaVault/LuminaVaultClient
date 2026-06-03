// LuminaVaultClient/LuminaVaultClient/Features/Analytics/TrendChartCard.swift
//
// HER-56 — full-size trend chart for one signal. Lifts the Line+Area
// treatment from `HealthDashboardCard.sparkline` (HER-118) but adds a
// header row, latest value, and visible axes for the standalone Deep
// Analytics dashboard.

import Charts
import SwiftUI

struct TrendChartCard: View {
    let series: TrendSeriesUIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            chart
                .frame(height: 140)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(series.title) — latest \(formattedLatest) \(series.unit)")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: series.systemImage)
                .font(.subheadline)
                .foregroundStyle(.tint)
            Text(series.title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formattedLatest)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(series.unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var formattedLatest: String {
        if series.latest == 0 { return "–" }
        if series.latest >= 1000 {
            return Int(series.latest.rounded()).formatted(.number)
        }
        return String(format: "%.1f", series.latest)
    }

    @ViewBuilder
    private var chart: some View {
        if series.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.5))
                Text("No data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Chart(series.points) { point in
                LineMark(
                    x: .value("Day", point.date),
                    y: .value(series.title, point.value),
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.tint)
                AreaMark(
                    x: .value("Day", point.date),
                    y: .value(series.title, point.value),
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.tint.opacity(0.12))
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
        }
    }
}

#Preview {
    let calendar = Calendar.current
    let now = Date()
    let points = (0..<14).map { index in
        TrendPointUIModel(
            date: calendar.date(byAdding: .day, value: -13 + index, to: now) ?? now,
            value: Double(2000 + index * 350 + (index % 3) * 600),
        )
    }
    return TrendChartCard(series: TrendSeriesUIModel(
        id: "health.steps",
        title: "Steps",
        systemImage: "figure.walk",
        unit: "steps",
        points: points,
        latest: points.last?.value ?? 0,
    ))
    .padding()
    .tint(.green)
}
