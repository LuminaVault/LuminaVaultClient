// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/CronsPreviewPanel.swift

import LuminaVaultShared
import SwiftUI

struct CronsPreviewPanel: View {
    @Environment(\.lvPalette) private var palette

    /// See `SkillsPreviewPanel` — a preview shows a glance, the header count
    /// and the overflow row carry the total.
    private static let previewLimit = 3

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
                    .fill(palette.surface.opacity(0.5))
                    .frame(height: 36)
                    .redacted(reason: .placeholder)
            } else if jobs.isEmpty {
                Text("No scheduled jobs yet.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(visibleJobs) { job in
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
                if overflow > 0 {
                    Text("+\(overflow) more")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(LVSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: 0.65)
    }

    private var visibleJobs: [DashboardCronJobDTO] {
        Array(jobs.prefix(Self.previewLimit))
    }

    private var overflow: Int {
        max(0, max(count, jobs.count) - visibleJobs.count)
    }
}
