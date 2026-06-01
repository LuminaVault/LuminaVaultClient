// LuminaVaultClient/LuminaVaultClient/Features/Jobs/JobDetailView.swift
//
// Lumina Jobs P1 — a single job's latest result + run history. The result is
// the most recent run's Markdown output (SkillRunDTO.markdown, persisted via
// M66). P2 will swap the Markdown body for a native BlockRenderer.

import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class JobDetailViewModel {
    enum LoadState: Equatable { case loading, loaded, failed(String) }
    var state: LoadState = .loading
    var runs: [SkillRunDTO] = []
    let job: SkillDTO
    private let client: SkillsClientProtocol

    init(client: SkillsClientProtocol, job: SkillDTO) {
        self.client = client
        self.job = job
    }

    func load() async {
        state = .loading
        do {
            runs = try await client.runs(name: job.name, limit: 50).runs
            state = .loaded
        } catch {
            state = .failed("Couldn't load this job's runs.")
        }
    }

    /// Most recent run that produced output.
    var latest: SkillRunDTO? { runs.first }
    var history: [SkillRunDTO] { Array(runs.dropFirst()) }
}

struct JobDetailView: View {

    @Environment(\.lvPalette) private var palette

    @State var vm: JobDetailViewModel

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            content
        }
        .navigationTitle(vm.job.title.isEmpty ? vm.job.name : vm.job.title)
        .navigationBarTitleDisplayMode(.inline)
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
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    latestResult
                    if !vm.history.isEmpty { historySection }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
    }

    @ViewBuilder
    private var latestResult: some View {
        if let latest = vm.latest, hasResult(latest) {
            VStack(alignment: .leading, spacing: 10) {
                Text(latest.startedAt, format: .dateTime.weekday().month().day().hour().minute())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                // P2 — native blocks when present; Markdown fallback otherwise.
                if let blocks = latest.blocks, !blocks.isEmpty {
                    BlockRenderer(blocks: blocks)
                } else if let body = latest.markdown, !body.isEmpty {
                    markdownBody(body)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lvGlassCard(cornerRadius: LVRadius.card, intensity: 0.7)
        } else if case .success = vm.latest?.status {
            Text("This run produced no output.")
                .font(.system(size: 13))
                .foregroundStyle(Color.lvTextMuted)
        } else {
            LVEmptyState(
                mascot: .idle,
                headline: "No results yet.",
                supporting: "This job hasn't produced a result yet. It'll appear here after its next run."
            )
        }
    }

    private func hasResult(_ run: SkillRunDTO) -> Bool {
        (run.blocks?.isEmpty == false) || (run.markdown?.isEmpty == false)
    }

    /// Reuses the app's Markdown render pattern (see TodayOutputDetailView):
    /// AttributedString with graceful plain-text fallback. P2 replaces this
    /// with a native BlockRenderer.
    @ViewBuilder
    private func markdownBody(_ body: String) -> some View {
        if let attr = try? AttributedString(
            markdown: body,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attr)
                .font(.system(size: 15))
                .foregroundStyle(palette.textPrimary)
                .textSelection(.enabled)
        } else {
            Text(body)
                .font(.system(size: 15))
                .foregroundStyle(palette.textPrimary)
                .textSelection(.enabled)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.textSecondary)
            ForEach(vm.history) { run in
                HStack(spacing: 10) {
                    Circle()
                        .fill(run.status == .success ? palette.primary : .red)
                        .frame(width: 6, height: 6)
                    Text(run.startedAt, format: .dateTime.month().day().hour().minute())
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(run.status.rawValue)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.lvTextMuted)
                }
                .padding(.vertical, 6)
            }
        }
    }
}
