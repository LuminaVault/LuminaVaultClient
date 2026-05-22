// LuminaVaultClient/LuminaVaultClient/Features/Home/HomeView.swift
//
// HER-244 — OS Shell Home/Dashboard screen. Replaces the kb-compile-only
// "Sync & Learn" home tab with a real control surface: mascot greeting,
// four cards (vault health · active tasks · recent insights · system
// status), and a three-button action row.

import Combine
import SwiftUI

struct HomeView: View {

    @Environment(\.lvPalette) private var palette

    @State var vm: HomeViewModel
    let onAskLumina: () -> Void
    /// HER-245/246/248/250 — pushed destinations from the dashboard cards.
    /// Owners are constructed by `MainTabView`; HomeView just navigates.
    let sessionsDestination: AnyView
    let tasksDestination: AnyView
    let insightsDestination: AnyView
    let serverConnectionDestination: AnyView

    var body: some View {
        NavigationStack {
            ZStack {
                palette.backgroundBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        DashboardGreetingView(displayName: vm.displayName)

                        NavigationLink { sessionsDestination } label: {
                            cardTile(systemImage: "bubble.left.and.bubble.right.fill", title: "Sessions", subtitle: "Chat history")
                        }
                        VaultHealthCardView(state: vm.stats)
                        NavigationLink { tasksDestination } label: {
                            ActiveTasksCardView(state: vm.tasks)
                        }
                        NavigationLink { insightsDestination } label: {
                            RecentInsightsCardView(state: vm.insights)
                        }
                        NavigationLink { serverConnectionDestination } label: {
                            SystemStatusCardView(isOnline: vm.isOnline)
                        }

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
            .lvNavBrand(position: .topLeading)
            .onReceive(NotificationCenter.default.publisher(for: BackendModeStore.modeChangedNotification)) { _ in
                // HER-262 — backend mode flipped; re-pull every card
                // against the new base URL within one event loop.
                Task { await vm.refresh() }
            }
            .task {
                await vm.refresh()
            }
        }
        .buttonStyle(.plain)
    }

    private func cardTile(systemImage: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Color.lvTextMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.backgroundBase.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(palette.primary.opacity(0.15), lineWidth: 1)
        )
    }
}
