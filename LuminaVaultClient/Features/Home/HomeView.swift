// LuminaVaultClient/LuminaVaultClient/Features/Home/HomeView.swift
//
// HER-244 — OS Shell Home/Dashboard screen. Replaces the kb-compile-only
// "Sync & Learn" home tab with a real control surface: mascot greeting,
// four cards (vault health · active tasks · recent insights · system
// status), and a three-button action row.

import SwiftUI

struct HomeView: View {
    @State var vm: HomeViewModel
    let onAskLumina: () -> Void

    var body: some View {
        ZStack {
            Color.lvNavy.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    DashboardGreetingView(displayName: vm.displayName)

                    VaultHealthCardView(state: vm.stats)
                    ActiveTasksCardView(state: vm.tasks)
                    RecentInsightsCardView(state: vm.insights)
                    SystemStatusCardView(isOnline: vm.isOnline)

                    DashboardActionRowView(
                        isCompiling: vm.compileViewModel.isBusy,
                        onNewSession: onAskLumina,
                        onTriggerCompile: { Task { await vm.triggerCompile() } },
                        onAskAnything: onAskLumina
                    )
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .refreshable {
                await vm.refresh()
            }
        }
        .lvBackground()
        .task {
            await vm.refresh()
        }
    }
}
