import LuminaVaultShared
import SwiftUI

struct PeriodKpiRow: View {
    @Environment(\.lvPalette) private var palette

    let stats: DashboardPeriodStats?
    var doneDestination: (() -> AnyView)?
    var capturesDestination: (() -> AnyView)?
    var skillsDestination: (() -> AnyView)?
    var tokensDestination: (() -> AnyView)?

    var body: some View {
        let values = stats ?? DashboardPeriodStats()
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            linkedTile("Done", values.done, values.previousDone, destination: doneDestination)
            linkedTile("Captures", values.captures, values.previousCaptures, destination: capturesDestination)
            linkedTile("Runs", values.skillRuns, values.previousSkillRuns, destination: skillsDestination)
            linkedTile("Tokens", values.tokens, values.previousTokens, destination: tokensDestination)
        }
    }

    @ViewBuilder
    private func linkedTile(
        _ label: String,
        _ value: Int,
        _ previous: Int,
        destination: (() -> AnyView)?
    ) -> some View {
        if let destination {
            NavigationLink { destination() } label: {
                tile(label, value, previous)
            }
        } else {
            tile(label, value, previous)
        }
    }

    private func tile(_ label: String, _ value: Int, _ previous: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(palette.textSecondary)
            Text(value.formatted())
                .font(.system(size: 20, weight: .black).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
            if let delta = Self.delta(value, previous) {
                Text(delta)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.glowPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
    }

    private static func delta(_ current: Int, _ previous: Int) -> String? {
        if current == 0 && previous == 0 { return nil }
        let diff = current - previous
        if diff == 0 { return "0 vs prior" }
        return "\(diff > 0 ? "+" : "")\(diff) vs prior"
    }
}
