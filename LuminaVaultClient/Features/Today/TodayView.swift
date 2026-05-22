// LuminaVaultClient/LuminaVaultClient/Features/Today/TodayView.swift
//
// HER-177 — Today tab. Mascot + streak header, scrollable feed of
// skill output cards, pull-to-refresh, empty state.

import LuminaVaultShared
import SwiftUI

struct TodayView: View {

    @Environment(\.lvPalette) private var palette

    @State var vm: TodayViewModel
    @Environment(NotificationRouter.self) private var router

    @State private var celebrate: Bool = false
    /// HER-264 — output being viewed in the inline detail sheet.
    @State private var detailOutput: SkillOutputDTO?
    /// HER-264 — output being shared via UIActivityViewController.
    @State private var shareOutput: SkillOutputDTO?

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        header
                        switch vm.state {
                        case .loading:
                            ProgressView().tint(palette.primary).padding()
                        case .failed(let message):
                            Text(message)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.lvTextMuted)
                                .padding(.horizontal)
                        case .loaded where vm.outputs.isEmpty:
                            emptyState
                        case .loaded:
                            ForEach(vm.outputs) { output in
                                TodayCardView(
                                    output: output,
                                    highlighted: vm.highlightedOutputID == output.id,
                                    onTap: { detailOutput = output },
                                    onShare: { shareOutput = output }
                                )
                                .id(output.id)
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    .padding(.vertical, 20)
                }
                .refreshable { await vm.refresh() }
                .onChange(of: vm.highlightedOutputID) { _, newID in
                    if let id = newID {
                        withAnimation { proxy.scrollTo(id, anchor: .top) }
                    }
                }
            }
        }
        .lvBackground()
        .sheet(item: $detailOutput) { output in
            TodayOutputDetailView(output: output)
        }
        .sheet(item: $shareOutput) { output in
            TodayShareSheet(activityItems: [
                "\(output.headline)\n\n\(output.body)\n\n— via Lumina",
            ])
        }
        .task { await vm.refresh() }
        .task(id: router.pendingDeepLink) {
            // HER-179 — when a digest push lands, mark the highlighted
            // output and fire the celebrating mascot for ~3 seconds.
            if case .today(let id) = router.pendingDeepLink {
                vm.celebrate(highlightOutputID: id)
                celebrate = true
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                celebrate = false
                _ = router.consume()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(spacing: 4) {
                HermieMascotView(
                    state: celebrate ? .celebrating : vm.mascotState,
                    size: 120,
                    fallbackImageName: "OnboardingMascot"
                )
                Text("Today")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [palette.accent, palette.primary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            Spacer()
            StreakCounter(days: vm.streakDays)
                .padding(.top, 12)
        }
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("Hermes is getting to know you.")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
            Text("Brief incoming at 7am tomorrow.")
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
    }
}
