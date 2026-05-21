// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/ActiveTasksCardView.swift
//
// HER-244 — surfaces in-flight Hermes operations. Empty by default until
// HER-246 wires real job tracking; this card already renders the eventual
// row layout so the upgrade is drop-in.

import LuminaVaultShared
import SwiftUI

struct ActiveTasksCardView: View {
    let state: HomeViewModel.CardState<[TaskDTO]>

    var body: some View {
        DashboardCardShell(title: "Active Tasks", icon: "gearshape.2.fill") {
            switch state {
            case .loading:
                placeholder(text: "Loading…")
            case .failed(let message):
                placeholder(text: message)
            case .loaded(let tasks) where tasks.isEmpty:
                placeholder(text: "No active tasks.")
            case .loaded(let tasks):
                VStack(spacing: 8) {
                    ForEach(tasks) { task in
                        row(task)
                    }
                }
            }
        }
    }

    private func placeholder(text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.lvTextMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 32, alignment: .leading)
    }

    private func row(_ task: TaskDTO) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(for: task.state))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color(for: task.state))
            VStack(alignment: .leading, spacing: 2) {
                Text(task.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.lvTextPrimary)
                    .lineLimit(1)
                if let progress = task.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.lvCyan)
                }
            }
            Spacer()
        }
    }

    private func icon(for state: TaskState) -> String {
        switch state {
        case .running: return "circle.dotted"
        case .queued: return "hourglass"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func color(for state: TaskState) -> Color {
        switch state {
        case .running: return .lvCyan
        case .queued: return .lvTextSub
        case .completed: return .lvAmber
        case .failed: return .red
        }
    }
}
