import LuminaVaultShared
import SwiftUI

struct CronsPreviewPanel: View {
    @Environment(\.lvPalette) private var palette

    let jobs: [DashboardCronJobDTO]
    let count: Int
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            HStack {
                Text("CRONS")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(palette.glowPrimary)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }

            if isLoading {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 36)
            } else if jobs.isEmpty {
                Text("No scheduled jobs yet.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(jobs) { job in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.name ?? job.id)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        Text(job.schedule ?? "schedule unknown")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
    }
}
