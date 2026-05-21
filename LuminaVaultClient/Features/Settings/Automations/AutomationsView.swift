// LuminaVaultClient/LuminaVaultClient/Features/Settings/Automations/AutomationsView.swift
//
// HER-178 — Settings → Automations. Inline toggle + cadence preset
// per skill. "What does this do?" disclosure shows bodyExcerpt.

import LuminaVaultShared
import SwiftUI

struct AutomationsView: View {
    @State var vm: AutomationsViewModel

    var body: some View {
        ZStack {
            Color.lvNavy.ignoresSafeArea()
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
            ProgressView().tint(.lvCyan)
        case .failed(let message):
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.lvTextMuted)
                .padding()
        case .loaded:
            List {
                ForEach(vm.skills) { skill in
                    skillRow(skill)
                        .listRowBackground(Color.lvNavy.opacity(0.5))
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func skillRow(_ skill: LuminaVaultShared.SkillDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                badge(for: skill.source)
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.lvTextPrimary)
                    Text(skill.descriptionText)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.lvTextSub)
                        .lineLimit(2)
                }
                Spacer()
                lastRunPill(skill)
                Toggle("", isOn: Binding(
                    get: { skill.enabled },
                    set: { newValue in Task { await vm.toggle(skill, enabled: newValue) } }
                ))
                .labelsHidden()
                .tint(.lvCyan)
            }

            if skill.enabled, skill.schedule != nil || skill.scheduleOverride != nil {
                Menu {
                    Button("Manifest default") { Task { await vm.setCadence(skill, cron: "") } }
                    Button("Daily 7am") { Task { await vm.setCadence(skill, cron: "0 7 * * *") } }
                    Button("Daily 8am") { Task { await vm.setCadence(skill, cron: "0 8 * * *") } }
                    Button("Daily 9am") { Task { await vm.setCadence(skill, cron: "0 9 * * *") } }
                    Button("Weekly Sun 6pm") { Task { await vm.setCadence(skill, cron: "0 18 * * 0") } }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                        Text(cadenceLabel(skill))
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.lvCyan)
                }
            }

            DisclosureGroup("What does this do?") {
                Text(skill.bodyExcerpt)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.lvTextSub)
                    .padding(.top, 4)
            }
            .font(.system(size: 12))
            .tint(Color.lvTextSub)
        }
        .padding(.vertical, 6)
    }

    private func badge(for source: SkillSource) -> some View {
        Text(source == .builtin ? "Default" : "Custom")
            .font(.system(size: 9, weight: .heavy))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background((source == .builtin ? Color.lvAmber : Color.lvCyan).opacity(0.18))
            .foregroundStyle(source == .builtin ? Color.lvAmber : Color.lvCyan)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func lastRunPill(_ skill: LuminaVaultShared.SkillDTO) -> some View {
        if let status = skill.lastStatus {
            Text(status.rawValue.capitalized)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color(status).opacity(0.18))
                .foregroundStyle(color(status))
                .clipShape(Capsule())
        }
    }

    private func color(_ status: SkillRunStatus) -> Color {
        switch status {
        case .success: .green
        case .running, .pending: .lvCyan
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
