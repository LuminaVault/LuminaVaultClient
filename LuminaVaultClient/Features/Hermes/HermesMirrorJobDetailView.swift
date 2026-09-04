// LuminaVaultClient/LuminaVaultClient/Features/Hermes/HermesMirrorJobDetailView.swift
//
// Hermes Companion Phase 2 — one mirrored job: what it produced, and the
// controls for it.
//
// The run history comes from LuminaVault's own rows, so this screen is
// readable while the user's Hermes is asleep. The controls are not — they go
// through to that machine. The failure banner is separate from the screen
// state for exactly that reason: an offline Hermes should leave the history
// on screen and say the control failed, not blank the page.

import LuminaVaultShared
import SwiftUI

struct HermesMirrorJobDetailView: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State var vm: HermesMirrorJobDetailViewModel
    @State private var showEditor = false
    @State private var confirmDelete = false
    let client: any HermesMirrorJobsClientProtocol

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            content
        }
        .navigationTitle(vm.title)
        .navigationBarTitleDisplayMode(.inline)
        .lvBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEditor = true } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    LVIconView(.ellipsis, size: 17, tint: palette.textPrimary)
                }
                .disabled(vm.isWorking)
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                HermesMirrorJobEditorView(
                    vm: HermesMirrorJobEditorViewModel(client: client, mode: .edit(vm.job)),
                    onSaved: { updated in vm.adopt(updated) }
                )
            }
        }
        .confirmationDialog(
            "Delete this job?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await vm.delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It stops running on your Hermes. Runs already collected stay in your vault.")
        }
        .onChange(of: vm.isDeleted) { _, deleted in
            if deleted { dismiss() }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().tint(palette.primary)
        case .failed(let failure):
            HermesMirrorFailureView(failure: failure, retry: { await vm.load() })
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: LVSpacing.lg) {
                    header
                    controls
                    if let error = vm.actionError { errorPanel(error) }
                    if let latest = vm.latest {
                        latestSection(latest)
                    } else {
                        LVEmptyState(
                            mascot: .idle,
                            headline: "Nothing collected yet.",
                            supporting: "Output appears here after the job's next run — or run it now."
                        )
                    }
                    if !vm.history.isEmpty { historySection }
                }
                .padding(.horizontal, LVSpacing.base)
                .padding(.vertical, LVSpacing.base)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            HStack(spacing: LVSpacing.sm) {
                if let schedule = vm.job.schedule, !schedule.isEmpty {
                    Label(schedule, systemImage: "clock")
                        .lvFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                if vm.job.paused {
                    Label("Paused", systemImage: "pause.fill")
                        .lvFont(.microTag)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                if let next = vm.job.nextRunAt, !vm.job.paused {
                    Text("next \(next, format: .relative(presentation: .named))")
                        .lvFont(.caption)
                        .foregroundStyle(Color.lvTextMuted)
                }
            }
            if let prompt = vm.job.prompt, !prompt.isEmpty {
                Text(prompt)
                    .lvFont(.callout)
                    .foregroundStyle(palette.textPrimary)
                    .textSelection(.enabled)
            }
            if let collected = vm.collectedAt {
                Text("Collected \(collected, format: .relative(presentation: .named))")
                    .lvFont(.caption)
                    .foregroundStyle(Color.lvTextMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        HStack(spacing: LVSpacing.md) {
            Button {
                Task { await vm.trigger() }
            } label: {
                Label("Run now", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.primary)
            .disabled(vm.isWorking)

            Button {
                Task { await vm.setPaused(!vm.job.paused) }
            } label: {
                Label(
                    vm.job.paused ? "Resume" : "Pause",
                    systemImage: vm.job.paused ? "play.circle" : "pause.fill"
                )
            }
            .buttonStyle(.bordered)
            .disabled(vm.isWorking)

            if vm.isWorking { ProgressView().tint(palette.primary) }
            Spacer()
        }
    }

    private func errorPanel(_ failure: HermesMirrorFailure) -> some View {
        VStack(alignment: .leading, spacing: LVSpacing.xs) {
            Text(failure.message)
                .lvFont(.callout)
                .foregroundStyle(.red)
            if let guidance = failure.guidance {
                Text(guidance)
                    .lvFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LVSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                .fill(Color.red.opacity(0.10))
        )
    }

    private func latestSection(_ run: HermesJobRunDTO) -> some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            Text("LATEST RUN")
                .lvFont(.kicker)
                .foregroundStyle(palette.textSecondary)
            HermesJobRunCard(run: run, expanded: true)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            Text("HISTORY")
                .lvFont(.kicker)
                .foregroundStyle(palette.textSecondary)
            ForEach(vm.history) { run in
                HermesJobRunCard(run: run, expanded: false)
            }
        }
    }
}

/// One collected run. `expanded` renders the output body; collapsed rows show
/// a three-line preview so a long history stays scannable.
struct HermesJobRunCard: View {
    @Environment(\.lvPalette) private var palette
    let run: HermesJobRunDTO
    let expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            HStack(spacing: LVSpacing.sm) {
                Circle()
                    .fill(statusTint)
                    .frame(width: 6, height: 6)
                Text(run.startedAt, format: .dateTime.weekday().month().day().hour().minute())
                    .lvFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                if let tokens = run.tokens, let output = tokens.output {
                    Text("\(output) tok")
                        .lvFont(.caption)
                        .foregroundStyle(Color.lvTextMuted)
                }
            }

            if let error = run.error, !error.isEmpty {
                Text(error)
                    .lvFont(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(expanded ? nil : 3)
            } else if let output = run.output, !output.isEmpty {
                outputBody(output)
            } else if run.status == .running {
                Text("Still running on your Hermes.")
                    .lvFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            } else {
                Text("No output.")
                    .lvFont(.caption)
                    .foregroundStyle(Color.lvTextMuted)
            }

            if let path = run.vaultFilePath, !path.isEmpty {
                Label(path, systemImage: "doc.text")
                    .lvFont(.caption)
                    .foregroundStyle(Color.lvTextMuted)
                    .lineLimit(1)
            }
        }
        .padding(LVSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lvGlassCard(cornerRadius: LVRadius.md, intensity: 0.6)
    }

    /// Same Markdown treatment the Today output detail uses: attributed
    /// where it parses, plain text where it does not.
    @ViewBuilder
    private func outputBody(_ body: String) -> some View {
        let rendered = (try? AttributedString(
            markdown: body,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(body)
        Text(rendered)
            .lvFont(.callout)
            .foregroundStyle(palette.textPrimary)
            .textSelection(.enabled)
            .lineLimit(expanded ? nil : 3)
    }

    private var statusTint: Color {
        switch run.status {
        case .ok: return palette.primary
        case .error: return .red
        case .running: return palette.accent
        }
    }
}
