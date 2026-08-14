import LuminaVaultShared
import SwiftUI

struct PeriodChipBar: View {
    @Environment(\.lvPalette) private var palette

    let period: DashboardPeriod
    let onChange: (DashboardPeriod) -> Void

    private let chips: [(DashboardPeriod, String)] = [
        (.today, "Today"),
        (.yesterday, "Yesterday"),
        (.week, "Week"),
        (.month, "Month"),
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(chips, id: \.0) { chip in
                Button(chip.1) { onChange(chip.0) }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(
                            period == chip.0
                                ? palette.glowPrimary.opacity(0.18)
                                : Color.white.opacity(0.04)
                        )
                    )
                    .overlay(
                        Capsule().stroke(
                            period == chip.0 ? palette.glowPrimary : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                    )
                    .foregroundStyle(period == chip.0 ? palette.glowPrimary : palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }
}
