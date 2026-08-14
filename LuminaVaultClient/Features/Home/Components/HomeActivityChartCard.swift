import Charts
import LuminaVaultShared
import SwiftUI

struct HomeActivityChartCard: View {
    @Environment(\.lvPalette) private var palette

    let series: [DashboardSeriesPoint]
    let period: DashboardPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACTIVITY")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(palette.glowPrimary)

            if series.isEmpty {
                Text("No activity in this window yet.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
            } else {
                Chart(series) { point in
                    BarMark(
                        x: .value("When", point.at),
                        y: .value("Activity", point.value)
                    )
                    .foregroundStyle(palette.glowPrimary.opacity(0.85))
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .frame(height: 140)
                .accessibilityLabel("Activity for \(period.rawValue)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
    }
}
