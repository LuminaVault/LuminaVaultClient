// LuminaVaultClient/LuminaVaultClient/Features/Settings/Skills/Components/SkillRowView.swift
//
// HER-247 — one row inside the Skills hub list.

import LuminaVaultShared
import SwiftUI

struct SkillRowView: View {
    let skill: LuminaVaultShared.SkillDTO
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(skill.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.lvTextPrimary)
                    .lineLimit(1)
                Text(skill.descriptionText)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.lvTextSub)
                    .lineLimit(2)
                lastRunFooter
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { skill.enabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .tint(.lvCyan)
        }
        .padding(.vertical, 6)
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(Color.lvCyan.opacity(0.18))
                .frame(width: 30, height: 30)
            Image(systemName: skill.source == .builtin ? "sparkle" : "puzzlepiece.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.lvCyan)
        }
    }

    @ViewBuilder
    private var lastRunFooter: some View {
        if let lastRunAt = skill.lastRunAt {
            HStack(spacing: 6) {
                statusPill
                Text("· \(Self.formatter.localizedString(for: lastRunAt, relativeTo: Date()))")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.lvTextMuted)
            }
        } else {
            Text("Never run")
                .font(.system(size: 11))
                .foregroundStyle(Color.lvTextMuted)
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if let status = skill.lastStatus {
            Text(status.rawValue.capitalized)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(pillColor(status).opacity(0.18))
                .foregroundStyle(pillColor(status))
                .clipShape(Capsule())
        }
    }

    private func pillColor(_ status: SkillRunStatus) -> Color {
        switch status {
        case .success: .green
        case .running, .pending: .lvCyan
        case .error: .red
        }
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
