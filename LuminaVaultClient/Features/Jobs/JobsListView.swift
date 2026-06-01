// LuminaVaultClient/LuminaVaultClient/Features/Jobs/JobsListView.swift
//
// Lumina Jobs P1 — the Jobs surface. A "Job" is a scheduled (cron) skill that
// runs in the background and produces results. This lists the user's jobs with
// schedule + last-run status; tapping opens the job's latest result + history.
// Reuses SkillsClientProtocol (jobs = skills with a `schedule`).

import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class JobsListViewModel {
    enum LoadState: Equatable { case loading, loaded, failed(String) }
    var state: LoadState = .loading
    var jobs: [SkillDTO] = []
    private let client: SkillsClientProtocol

    init(client: SkillsClientProtocol) { self.client = client }

    func load() async {
        state = .loading
        do {
            let response = try await client.list()
            // Jobs = scheduled skills (a cron schedule, or a user override).
            jobs = response.skills
                .filter { ($0.schedule?.isEmpty == false) || ($0.scheduleOverride?.isEmpty == false) }
                .sorted { ($0.lastRunAt ?? .distantPast) > ($1.lastRunAt ?? .distantPast) }
            state = .loaded
        } catch {
            state = .failed("Couldn't load your jobs.")
        }
    }
}

struct JobsListView: View {

    @Environment(\.lvPalette) private var palette

    @State var vm: JobsListViewModel
    let client: SkillsClientProtocol

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Jobs")
        .lvBackground()
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().tint(palette.primary)
        case .failed(let message):
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.lvTextMuted)
                .padding()
        case .loaded where vm.jobs.isEmpty:
            LVEmptyState(
                mascot: .idle,
                headline: "No jobs yet.",
                supporting: "Ask Lumina for something recurring — daily stock prices, weekly AI summaries — and it'll run here in the background."
            )
        case .loaded:
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(vm.jobs) { job in
                        NavigationLink {
                            JobDetailView(vm: JobDetailViewModel(client: client, job: job))
                        } label: {
                            JobRow(job: job)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
        }
    }
}

/// One job card — title, schedule, last-run status dot + relative time.
private struct JobRow: View {
    @Environment(\.lvPalette) private var palette
    let job: SkillDTO

    var body: some View {
        HStack(spacing: 12) {
            statusDot
            VStack(alignment: .leading, spacing: 4) {
                Text(job.title.isEmpty ? job.name : job.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                HStack(spacing: 8) {
                    if let schedule = job.schedule ?? job.scheduleOverride {
                        Label(schedule, systemImage: "clock")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                    }
                    if let last = job.lastRunAt {
                        Text(last, format: .relative(presentation: .named))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.lvTextMuted)
                    }
                }
            }
            Spacer()
            LVIconView(.chevronRight, size: 13, tint: palette.textSecondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                .fill(palette.surface.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                .stroke(palette.glowPrimary.opacity(0.18), lineWidth: 1)
        )
    }

    private var statusDot: some View {
        Circle()
            .fill(color(for: job.lastStatus))
            .frame(width: 8, height: 8)
            .shadow(color: color(for: job.lastStatus).opacity(0.6), radius: 4)
    }

    private func color(for status: SkillRunStatus?) -> Color {
        switch status {
        case .success: return palette.primary
        case .error: return .red
        case .running, .pending: return palette.accent
        case nil: return palette.textSecondary.opacity(0.4)
        }
    }
}
