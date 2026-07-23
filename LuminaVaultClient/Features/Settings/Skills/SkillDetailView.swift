// LuminaVaultClient/LuminaVaultClient/Features/Settings/Skills/SkillDetailView.swift
//
// HER-247 — push destination from SkillsHubView. Renders full skill
// description, cadence picker, channel picker, sparkline, recent
// runs, and an enable toggle in the navigation bar.

import LuminaVaultShared
import SwiftUI

struct SkillDetailView: View {

    @Environment(\.lvPalette) private var palette

    @State var vm: SkillDetailViewModel

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: LVSpacing.lg) {
                    header
                    descriptionSection
                    cadenceSection
                    channelSection
                    curatorProtectionSection
                    usageSection
                    recentRunsSection
                }
                .padding(.horizontal, LVSpacing.lg)
                .padding(.vertical, LVSpacing.base)
            }
        }
        .lvBackground()
        .navigationTitle(vm.skill.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle("", isOn: Binding(
                    get: { vm.skill.enabled },
                    set: { newValue in Task { await vm.toggle(enabled: newValue) } }
                ))
                .labelsHidden()
                .tint(palette.primary)
            }
        }
        .task { await vm.loadRuns() }
    }

    private var header: some View {
        HStack(spacing: LVSpacing.md) {
            // HER-291: kept as Image — runtime symbol name (sparkle/puzzlepiece.fill not in LVIcon)
            Image(systemName: vm.skill.source == .builtin ? "sparkle" : "puzzlepiece.fill")
                .font(.system(size: 18, weight: .semibold)) // TODO HER-icon-tokens: scope deferred per HER-289
                .foregroundStyle(palette.primary)
            Text(vm.skill.source == .builtin ? "Built-in" : "Custom")
                .font(LVTypography.caption.font.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)
                .tracking(0.6)
            Spacer()
        }
    }

    private var descriptionSection: some View {
        Text(vm.skill.descriptionText)
            .font(LVTypography.callout.font)
            .foregroundStyle(palette.textPrimary)
    }

    private var cadenceSection: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            sectionLabel("Cadence")
            CadencePicker(
                scheduleOverride: Binding(
                    get: { vm.skill.scheduleOverride },
                    set: { _ in /* committed via onCommit closure */ }
                ),
                onCommit: { cron in Task { await vm.setCadence(cron) } }
            )
            if let manifest = vm.skill.schedule {
                Text("Manifest default: `\(manifest)`")
                    .font(LVTypography.caption.font.monospaced())
                    .foregroundStyle(Color.lvTextMuted)
            }
        }
    }

    private var channelSection: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            sectionLabel("Notification channel")
            Picker("", selection: Binding(
                get: { vm.skill.apnsCategory ?? .digest },
                set: { newValue in Task { await vm.setChannel(newValue) } }
            )) {
                Text("Digest").tag(APNSCategory.digest)
                Text("Nudge").tag(APNSCategory.nudge)
                Text("Chat").tag(APNSCategory.chat)
            }
            .pickerStyle(.segmented)
        }
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            sectionLabel("Usage (14 days)")
            UsageSparklineView(points: vm.sparkline)
        }
    }

    @ViewBuilder
    private var curatorProtectionSection: some View {
        if let resource = vm.curatorResource {
            VStack(alignment: .leading, spacing: LVSpacing.sm) {
                sectionLabel("Curator protection")
                Toggle("Pin this skill", isOn: Binding(
                    get: { resource.pinned },
                    set: { pinned in Task { await vm.setPinned(pinned) } }
                ))
                Text("Pinned skills are never consolidated, marked stale, or archived.")
                    .font(LVTypography.caption.font)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var recentRunsSection: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            sectionLabel("Recent runs")
            switch vm.runsState {
            case .loading:
                ProgressView().tint(palette.primary)
            case .failed(let message):
                Text(message)
                    .font(LVTypography.caption.font)
                    .foregroundStyle(Color.lvTextMuted)
            case .loaded where vm.runs.isEmpty:
                Text("No runs yet.")
                    .font(LVTypography.footnote.font)
                    .foregroundStyle(Color.lvTextMuted)
            case .loaded:
                VStack(alignment: .leading, spacing: LVSpacing.sm) {
                    ForEach(vm.runs.prefix(15)) { run in
                        runRow(run)
                    }
                }
            }
        }
    }

    private func runRow(_ run: SkillRunDTO) -> some View {
        HStack(spacing: LVSpacing.sm) {
            Circle()
                .fill(color(for: run.status))
                .frame(width: 6, height: 6)
            Text(Self.formatter.localizedString(for: run.startedAt, relativeTo: Date()))
                .font(LVTypography.caption.font)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Text(run.status.rawValue)
                .font(LVTypography.microTag.font)
                .foregroundStyle(color(for: run.status))
        }
        .padding(.vertical, LVSpacing.xs)
    }

    private func color(for status: SkillRunStatus) -> Color {
        switch status {
        case .success: .green
        case .running, .pending: palette.primary
        case .error: .red
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(LVTypography.caption.font.weight(.semibold))
            .foregroundStyle(palette.textSecondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
