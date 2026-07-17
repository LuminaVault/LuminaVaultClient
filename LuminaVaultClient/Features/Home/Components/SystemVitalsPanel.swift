// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/SystemVitalsPanel.swift
//
// Left-column style vitals for the Command Center: skills, active jobs,
// memories, sessions, streak, tokens.

import LuminaVaultShared
import SwiftUI

struct SystemVitalsPanel: View {
    @Environment(\.lvPalette) private var palette

    let home: HomeSummaryResponse?
    let tokenTotal: Int?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            Text("SYSTEM VITALS")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(palette.glowPrimary)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: LVSpacing.sm
            ) {
                vital("Skills", value: count(home?.skillsCount))
                vital("Active", value: count(home?.activeJobsCount))
                vital("Memories", value: count(home?.memoriesTotal))
                vital("Today", value: count(home?.memoriesToday))
                vital("Sessions", value: count(home?.sessionsCount))
                vital("Streak", value: home.map { "\($0.streakDays)d" } ?? "—")
                vital("Tokens", value: tokenLabel)
                vital("Badges", value: count(home?.badgesEarned))
            }
        }
        .padding(LVSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: 0.65)
        .redacted(reason: isLoading ? .placeholder : [])
    }

    private func vital(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, LVSpacing.xs)
    }

    private func count(_ value: Int?) -> String {
        value.map(formatCompact) ?? "—"
    }

    private var tokenLabel: String {
        guard let tokenTotal else { return "—" }
        return formatCompact(tokenTotal)
    }

    private func formatCompact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}
