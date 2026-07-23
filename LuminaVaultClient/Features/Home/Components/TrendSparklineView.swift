// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/TrendSparklineView.swift
//
// Command Center — compact 30-day AI-activity sparkline fed by
// GET /v1/analytics/overview (`AnalyticsOverviewResponse.daily`).
// Axis-free by design: this is a pulse readout, not an analysis surface
// (the Analytics tab owns the full chart).

import Charts
import LuminaVaultShared
import SwiftUI

struct TrendSparklineView: View {

    @Environment(\.lvPalette) private var palette

    let daily: [AnalyticsDailyPointDTO]
    let isLoading: Bool

    var body: some View {
        DashboardCardShell(title: "Activity Trend", icon: "waveform.path.ecg") {
            if daily.isEmpty {
                Text(isLoading ? "Loading…" : "No activity recorded yet.")
                    .font(.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(totalRequests.formatted())
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(palette.textPrimary)
                            .contentTransition(.numericText())
                        Text("AI requests · 30d")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }

                    Chart(daily, id: \.date) { point in
                        AreaMark(
                            x: .value("Day", point.date),
                            y: .value("Requests", point.aiRequests)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [palette.accent.opacity(0.35), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Day", point.date),
                            y: .value("Requests", point.aiRequests)
                        )
                        .foregroundStyle(palette.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 56)
                    .accessibilityLabel("Thirty-day activity trend, \(totalRequests) AI requests")
                }
            }
        }
    }

    private var totalRequests: Int {
        daily.reduce(0) { $0 + $1.aiRequests }
    }
}
