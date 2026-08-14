import Charts
import LuminaVaultShared
import SwiftUI

struct HomeMixDonutCard: View {
    @Environment(\.lvPalette) private var palette

    let mix: DashboardPeriodMix?

    private struct Slice: Identifiable {
        let id: String
        let value: Int
        let color: Color
    }

    private var slices: [Slice] {
        let mix = mix ?? DashboardPeriodMix()
        return [
            Slice(id: "Captures", value: mix.captures, color: palette.glowPrimary),
            Slice(id: "Jobs", value: mix.jobs, color: palette.secondary),
            Slice(id: "Skills", value: mix.skills, color: .purple),
            Slice(id: "Chats", value: mix.chats, color: .mint),
        ].filter { $0.value > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MIX")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(palette.glowPrimary)

            if slices.isEmpty {
                Text("Nothing to break down in this window.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
            } else {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value(slice.id, slice.value),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .foregroundStyle(slice.color)
                }
                .frame(height: 140)
                .accessibilityLabel("Activity mix")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
    }
}
