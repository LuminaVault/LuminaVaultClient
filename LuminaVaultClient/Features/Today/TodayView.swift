// LuminaVaultClient/LuminaVaultClient/Features/Today/TodayView.swift
//
// HER-177 — Today tab. Mascot + streak header, scrollable feed of
// skill output cards, pull-to-refresh, empty state.

import LuminaVaultShared
import SwiftUI

struct TodayView: View {
    @State var vm: TodayViewModel
    @Environment(NotificationRouter.self) private var router

    @State private var celebrate: Bool = false

    var body: some View {
        ZStack {
            Color.lvNavy.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        header
                        switch vm.state {
                        case .loading:
                            ProgressView().tint(.lvCyan).padding()
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
                                    onTap: { /* TODO HER-107/HER-105: route to memo/memory/vault file */ },
                                    onShare: { /* TODO: present UIActivityViewController with Lumina watermark */ }
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
                            colors: [.lvAmber, .lvCyan],
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
                .foregroundStyle(Color.lvTextPrimary)
                .multilineTextAlignment(.center)
            Text("Brief incoming at 7am tomorrow.")
                .font(.system(size: 13))
                .foregroundStyle(Color.lvTextSub)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
    }
}
