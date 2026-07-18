// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/ActiveJobsPanel.swift

import LuminaVaultShared
import SwiftUI

struct ActiveJobsPanel: View {
    @Environment(\.lvPalette) private var palette

    let jobs: [TaskDTO]
    let isLoading: Bool
    var onSeeAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.md) {
            HStack {
                Text("ACTIVE JOBS")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(palette.glowPrimary)
                Spacer()
                if let onSeeAll {
                    Button("See all", action: onSeeAll)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.glowPrimary)
                }
            }

            if isLoading {
                ForEach(0..<2, id: \.self) { _ in
                    rowSkeleton
                }
            } else if jobs.isEmpty {
                Text("No active jobs — your agent is idle.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.vertical, LVSpacing.sm)
            } else {
                ForEach(jobs) { job in
                    HStack(alignment: .top, spacing: LVSpacing.sm) {
                        Circle()
                            .fill(stateColor(job.state))
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.label)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1)
                            Text("\(job.kind) · \(job.state.rawValue)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(LVSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: 0.65)
    }

    private var rowSkeleton: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(palette.surface.opacity(0.5))
            .frame(height: 36)
            .redacted(reason: .placeholder)
    }

    private func stateColor(_ state: TaskState) -> Color {
        switch state {
        case .running: return palette.glowPrimary
        case .queued: return palette.accent
        case .failed: return .red.opacity(0.85)
        case .completed: return .green.opacity(0.85)
        }
    }
}
