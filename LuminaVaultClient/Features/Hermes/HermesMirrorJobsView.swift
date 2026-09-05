// LuminaVaultClient/LuminaVaultClient/Features/Hermes/HermesMirrorJobsView.swift
//
// Hermes Companion Phase 2 "Collect" — the jobs on the user's own Hermes.
//
// The `snapshot` banner is not decoration. These rows can come from the last
// mirror sync when the user's machine is unreachable, and a paused job that
// was resumed on the machine would otherwise read as current.

import LuminaVaultShared
import SwiftUI

struct HermesMirrorJobsView: View {
    @Environment(\.lvPalette) private var palette

    @State var vm: HermesMirrorJobsListViewModel
    @State private var showEditor = false
    let client: any HermesMirrorJobsClientProtocol

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Hermes Jobs")
        .lvBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEditor = true } label: {
                    Label("New job", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                HermesMirrorJobEditorView(
                    vm: HermesMirrorJobEditorViewModel(client: client, mode: .create),
                    onSaved: { _ in Task { await vm.load() } }
                )
            }
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
        case .loaded where vm.jobs.isEmpty:
            LVEmptyState(
                mascot: .idle,
                headline: "No scheduled jobs.",
                supporting: "Jobs run on your own Hermes on a schedule and file their output back here. Add one and it appears on Today when it runs."
            )
        case .loaded:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LVSpacing.md) {
                    if vm.source == .snapshot { snapshotBanner }
                    section("SCHEDULED", jobs: vm.active)
                    section("PAUSED", jobs: vm.paused)
                }
                .padding(.horizontal, LVSpacing.base)
                .padding(.top, LVSpacing.md)
                .padding(.bottom, LVSpacing.hero + LVSpacing.xxl)
            }
        }
    }

    private var snapshotBanner: some View {
        HStack(alignment: .top, spacing: LVSpacing.sm) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(palette.textSecondary)
            Text("Your Hermes is unreachable — showing the last synced copy. Changes will fail until it's back.")
                .lvFont(.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(LVSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                .fill(palette.surface.opacity(0.5))
        )
    }

    @ViewBuilder
    private func section(_ title: String, jobs: [HermesMirroredJobDTO]) -> some View {
        if !jobs.isEmpty {
            Text(title)
                .lvFont(.kicker)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, LVSpacing.sm)
            ForEach(jobs) { job in
                NavigationLink {
                    HermesMirrorJobDetailView(
                        vm: HermesMirrorJobDetailViewModel(client: client, job: job),
                        client: client
                    )
                } label: {
                    HermesMirrorJobRow(job: job)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct HermesMirrorJobRow: View {
    @Environment(\.lvPalette) private var palette
    let job: HermesMirroredJobDTO

    var body: some View {
        HStack(alignment: .top, spacing: LVSpacing.md) {
            VStack(alignment: .leading, spacing: LVSpacing.sm) {
                Text(job.name ?? job.hermesJobID)
                    .lvFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: LVSpacing.sm) {
                    if job.paused {
                        Label("Paused", systemImage: "pause.fill")
                            .lvFont(.microTag)
                            .foregroundStyle(palette.textSecondary)
                    }
                    if let schedule = job.schedule, !schedule.isEmpty {
                        Label(schedule, systemImage: "clock")
                            .lvFont(.caption)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                    if let last = job.lastRunAt {
                        Text(last, format: .relative(presentation: .named))
                            .lvFont(.caption)
                            .foregroundStyle(Color.lvTextMuted)
                    }
                }
            }
            Spacer(minLength: LVSpacing.sm)
            LVIconView(.chevronRight, size: 13, tint: palette.textSecondary)
                .padding(.top, LVSpacing.xs)
        }
        .opacity(job.paused ? 0.6 : 1)
        .padding(LVSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                .fill(palette.surface.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
    }
}

/// Shared failure panel for the Phase 2 screens.
struct HermesMirrorFailureView: View {
    @Environment(\.lvPalette) private var palette
    let failure: HermesMirrorFailure
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: LVSpacing.md) {
            Text(failure.message)
                .lvFont(.body)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
            if let guidance = failure.guidance {
                Text(guidance)
                    .lvFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if failure.isRetryable {
                Button("Try again") { Task { await retry() } }
                    .buttonStyle(.bordered)
            }
        }
        .padding(LVSpacing.xl)
    }
}
