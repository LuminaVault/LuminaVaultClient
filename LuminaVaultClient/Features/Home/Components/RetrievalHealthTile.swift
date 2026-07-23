// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/RetrievalHealthTile.swift
//
// Command Center — recall-quality tile fed by
// GET /v1/analytics/retrieval-health (M107 telemetry + weekly leak
// report). Hit rate %, trend arrow, and open-leak count.

import LuminaVaultShared
import SwiftUI

struct RetrievalHealthTile: View {

    @Environment(\.lvPalette) private var palette

    let health: RetrievalHealthResponse?
    let isLoading: Bool

    var body: some View {
        DashboardCardShell(title: "Recall Health", icon: "antenna.radiowaves.left.and.right") {
            if let health, health.eventsCount > 0, let hitRate = health.hitRate {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(hitRate, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(palette.textPrimary)
                        trendBadge(health.trend)
                    }
                    Text(leakLine(health))
                        .font(.caption)
                        .foregroundStyle(health.leakCount > 0 ? .orange : palette.textSecondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text(isLoading ? "Loading…" : "No retrieval data yet — recall stats appear once you start chatting with your memories.")
                    .font(.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            }
        }
    }

    private func leakLine(_ health: RetrievalHealthResponse) -> String {
        if health.leakCount == 0 { return "No open leaks · \(health.eventsCount) retrievals" }
        return "\(health.leakCount) open leak\(health.leakCount == 1 ? "" : "s") · \(health.eventsCount) retrievals"
    }

    @ViewBuilder
    private func trendBadge(_ trend: RetrievalHealthResponse.Trend) -> some View {
        let (symbol, tint, label): (String, Color, String) = switch trend {
        case .improving: ("arrow.up.right", .green, "improving")
        case .steady: ("arrow.right", palette.textSecondary, "steady")
        case .declining: ("arrow.down.right", .orange, "declining")
        }
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.caption)
        }
        .foregroundStyle(tint)
        .accessibilityLabel("Trend \(label)")
    }
}
