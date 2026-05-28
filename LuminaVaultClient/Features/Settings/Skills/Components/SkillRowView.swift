// LuminaVaultClient/LuminaVaultClient/Features/Settings/Skills/Components/SkillRowView.swift
//
// HER-247 — one row inside the Skills hub list.

import LuminaVaultShared
import SwiftUI

struct SkillRowView: View {

    @Environment(\.lvPalette) private var palette

    let skill: LuminaVaultShared.SkillDTO
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: LVSpacing.md) {
            icon
            VStack(alignment: .leading, spacing: LVSpacing.xs) {
                Text(skill.name)
                    .font(LVTypography.fieldLabel.font)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(skill.descriptionText)
                    .font(LVTypography.caption.font)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                lastRunFooter
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { skill.enabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .tint(palette.primary)
        }
        .padding(.vertical, LVSpacing.sm)
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(palette.primary.opacity(0.18))
                .frame(width: 30, height: 30)
            // HER-291: kept as Image — runtime symbol name (sparkle/puzzlepiece.fill not in LVIcon)
            Image(systemName: skill.source == .builtin ? "sparkle" : "puzzlepiece.fill")
                .font(.system(size: 13, weight: .semibold)) // TODO HER-icon-tokens: scope deferred per HER-289
                .foregroundStyle(palette.primary)
        }
    }

    @ViewBuilder
    private var lastRunFooter: some View {
        if let lastRunAt = skill.lastRunAt {
            HStack(spacing: LVSpacing.sm) {
                statusPill
                Text("· \(Self.formatter.localizedString(for: lastRunAt, relativeTo: Date()))")
                    .font(LVTypography.caption.font)
                    .foregroundStyle(Color.lvTextMuted)
            }
        } else {
            Text("Never run")
                .font(LVTypography.caption.font)
                .foregroundStyle(Color.lvTextMuted)
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if let status = skill.lastStatus {
            Text(status.rawValue.capitalized)
                .font(LVTypography.microTag.font)
                .padding(.horizontal, LVSpacing.sm)
                .padding(.vertical, LVSpacing.hairline)
                .background(pillColor(status).opacity(0.18))
                .foregroundStyle(pillColor(status))
                .clipShape(Capsule())
        }
    }

    private func pillColor(_ status: SkillRunStatus) -> Color {
        switch status {
        case .success: .green
        case .running, .pending: palette.primary
        case .error: .red
        }
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
