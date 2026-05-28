// LuminaVaultClient/LuminaVaultClient/Features/Settings/Automations/AutomationsView.swift
//
// HER-178 — Settings → Automations. Inline toggle + cadence preset
// per skill. "What does this do?" disclosure shows bodyExcerpt.

import LuminaVaultShared
import SwiftUI

struct AutomationsView: View {

    @Environment(\.lvPalette) private var palette

    @State var vm: AutomationsViewModel

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Automations")
        .lvBackground()
        .task { await vm.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().tint(palette.primary)
        case .failed(let message):
            Text(message)
                .font(LVTypography.footnote.font)
                .foregroundStyle(Color.lvTextMuted)
                .padding()
        case .loaded:
            List {
                ForEach(vm.skills) { skill in
                    skillRow(skill)
                        .listRowBackground(palette.backgroundBase.opacity(0.5))
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func skillRow(_ skill: LuminaVaultShared.SkillDTO) -> some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            HStack(spacing: LVSpacing.md) {
                badge(for: skill.source)
                VStack(alignment: .leading, spacing: LVSpacing.hairline) {
                    Text(skill.name)
                        .font(LVTypography.fieldLabel.font)
                        .foregroundStyle(palette.textPrimary)
                    Text(skill.descriptionText)
                        .font(LVTypography.caption.font)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                lastRunPill(skill)
                Toggle("", isOn: Binding(
                    get: { skill.enabled },
                    set: { newValue in Task { await vm.toggle(skill, enabled: newValue) } }
                ))
                .labelsHidden()
                .tint(palette.primary)
            }

            if skill.enabled, skill.schedule != nil || skill.scheduleOverride != nil {
                Menu {
                    Button("Manifest default") { Task { await vm.setCadence(skill, cron: "") } }
                    Button("Daily 7am") { Task { await vm.setCadence(skill, cron: "0 7 * * *") } }
                    Button("Daily 8am") { Task { await vm.setCadence(skill, cron: "0 8 * * *") } }
                    Button("Daily 9am") { Task { await vm.setCadence(skill, cron: "0 9 * * *") } }
                    Button("Weekly Sun 6pm") { Task { await vm.setCadence(skill, cron: "0 18 * * 0") } }
                } label: {
                    HStack(spacing: LVSpacing.xs) {
                        LVIconView(.clockFill, size: 11, tint: palette.primary, weight: .semibold)
                        Text(cadenceLabel(skill))
                        LVIconView(.chevronUpChevronDown, size: 11, tint: palette.primary, weight: .semibold)
                    }
                    .font(LVTypography.microTag.font)
                    .foregroundStyle(palette.primary)
                }
            }

            DisclosureGroup("What does this do?") {
                Text(skill.bodyExcerpt)
                    .font(LVTypography.caption.font.monospaced())
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, LVSpacing.xs)
            }
            .font(LVTypography.caption.font)
            .tint(palette.textSecondary)
        }
        .padding(.vertical, LVSpacing.sm)
    }

    private func badge(for source: SkillSource) -> some View {
        Text(source == .builtin ? "Default" : "Custom")
            .font(LVTypography.microTag.font)
            .padding(.horizontal, LVSpacing.sm)
            .padding(.vertical, LVSpacing.xs)
            .background((source == .builtin ? palette.accent : palette.primary).opacity(0.18))
            .foregroundStyle(source == .builtin ? palette.accent : palette.primary)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func lastRunPill(_ skill: LuminaVaultShared.SkillDTO) -> some View {
        if let status = skill.lastStatus {
            Text(status.rawValue.capitalized)
                .font(LVTypography.microTag.font)
                .padding(.horizontal, LVSpacing.sm)
                .padding(.vertical, LVSpacing.hairline)
                .background(color(status).opacity(0.18))
                .foregroundStyle(color(status))
                .clipShape(Capsule())
        }
    }

    private func color(_ status: SkillRunStatus) -> Color {
        switch status {
        case .success: .green
        case .running, .pending: palette.primary
        case .error: .red
        }
    }

    private func cadenceLabel(_ skill: LuminaVaultShared.SkillDTO) -> String {
        if let override = skill.scheduleOverride {
            switch override {
            case "0 7 * * *": return "Daily 7am"
            case "0 8 * * *": return "Daily 8am"
            case "0 9 * * *": return "Daily 9am"
            case "0 18 * * 0": return "Weekly Sun 6pm"
            default: return "Custom"
            }
        }
        if skill.schedule != nil { return "Manifest default" }
        return "On demand"
    }
}
