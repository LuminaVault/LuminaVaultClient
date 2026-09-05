// LuminaVaultClient/LuminaVaultClient/Features/Hermes/HermesRunsListView.swift
//
// Hermes Companion Phase 1 — the runs you have started, newest first.
//
// Runs waiting on an approval are hoisted to their own section at the top:
// they are the only rows blocked on the person reading the screen, and a
// blocked run that scrolls out of sight is a run that never finishes.

import LuminaVaultShared
import SwiftUI

struct HermesRunsListView: View {
    @Environment(\.lvPalette) private var palette

    @State var vm: HermesRunsListViewModel
    let client: any HermesRunsClientProtocol

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Agent Runs")
        .lvBackground()
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().tint(palette.primary)
        case .failed(let failure):
            failureState(failure)
        case .loaded where vm.runs.isEmpty:
            LVEmptyState(
                mascot: .idle,
                headline: "No runs yet.",
                supporting: "Ask Hermes to do something from the chat composer — \"Run as agent\" — and it works on your own machine while you watch from here."
            )
        case .loaded:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LVSpacing.md) {
                    section("NEEDS YOU", runs: vm.waitingForApproval)
                    section("RUNNING", runs: vm.active)
                    section("FINISHED", runs: vm.finished)
                }
                .padding(.horizontal, LVSpacing.base)
                .padding(.top, LVSpacing.md)
                .padding(.bottom, LVSpacing.hero + LVSpacing.xxl)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, runs: [HermesRunDTO]) -> some View {
        if !runs.isEmpty {
            Text(title)
                .lvFont(.kicker)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, LVSpacing.sm)
            ForEach(runs) { run in
                NavigationLink {
                    HermesRunDetailView(vm: HermesRunDetailViewModel(client: client, run: run))
                } label: {
                    HermesRunRow(run: run)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func failureState(_ failure: HermesRunsFailure) -> some View {
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
                Button("Try again") { Task { await vm.load() } }
                    .buttonStyle(.bordered)
            }
        }
        .padding(LVSpacing.xl)
    }
}

struct HermesRunRow: View {
    @Environment(\.lvPalette) private var palette
    let run: HermesRunDTO

    var body: some View {
        HStack(alignment: .top, spacing: LVSpacing.md) {
            VStack(alignment: .leading, spacing: LVSpacing.sm) {
                Text(run.prompt)
                    .lvFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: LVSpacing.sm) {
                    HermesRunStatusBadge(status: run.status)
                    Text(run.startedAt, format: .relative(presentation: .named))
                        .lvFont(.caption)
                        .foregroundStyle(Color.lvTextMuted)
                    if let event = run.lastEvent, !event.isEmpty, !run.status.isTerminal {
                        Text(event)
                            .lvFont(.caption)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: LVSpacing.sm)
            LVIconView(.chevronRight, size: 13, tint: palette.textSecondary)
                .padding(.top, LVSpacing.xs)
        }
        .padding(LVSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                .fill(palette.surface.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                .stroke(
                    run.status == .waitingForApproval
                        ? palette.glowPrimary.opacity(0.5)
                        : palette.surfaceStroke,
                    lineWidth: 1
                )
        )
    }
}
