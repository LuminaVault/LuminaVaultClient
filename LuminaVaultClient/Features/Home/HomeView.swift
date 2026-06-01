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
    /// Switches the root tab selection. Quick-action cards that target a
    /// tab (Spaces, AI) call this instead of pushing a duplicate screen.
    /// Pass tab ids matching `MainTabView.tabIds` ("workspaces", "think").
    var onSelectTab: (String) -> Void = { _ in }
    /// HER-245/246/248/250 — pushed destinations from the dashboard cards.
    /// Owners are constructed by `MainTabView`; HomeView just navigates.
    let sessionsDestination: AnyView
    let tasksDestination: AnyView
    let insightsDestination: AnyView
    let serverConnectionDestination: AnyView
    /// HER-243 — surfaces demoted from the tab bar in the 5-tab redesign.
    /// Optional so existing call sites (and unit tests) keep compiling
    /// without forcing every variant to wire every destination.
    var skillsDestination: AnyView? = nil
    var todayDestination: AnyView? = nil
    var visualSearchDestination: AnyView? = nil
    /// HER-118 — Health card pushes the sparkline dashboard. Optional so
    /// older call sites (tests, previews) keep compiling without wiring
    /// the new screen.
    var healthDestination: AnyView? = nil
    /// Achievements screen — pushed by tapping the player-profile HUD.
    /// Optional so older call sites (tests, previews) keep compiling.
    var achievementsDestination: AnyView? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    // Header mascot avatar = quick-access shortcut to the most-used settings.
    // Full Settings still lives behind the "..." (More) tab.
    @State private var showQuickSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                // Deep cosmic gradients
                RadialGradient(
                    colors: [palette.glowPrimary.opacity(0.12), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 500
                ).ignoresSafeArea()
                
                RadialGradient(
                    colors: [palette.accent.opacity(0.08), .clear],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: 600
                ).ignoresSafeArea()
                
                // HER-304 — subtle neural-network particle field anchored
                // to the top half of the screen. Reads §13.4 placement rule:
                // hero surface, subtle intensity, no scroll interaction.
                Color.clear
                    .lvParticleBackground(intensity: .subtle)
                    .frame(maxHeight: 420)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)

                ScrollView {
                    VStack(spacing: 40) {
                        // HER-304 — Mascot hero. Stitch reference places the
                        // mascot prominently below the wordmark; previously
                        // the Home tab had no mascot at all.
                        MascotHero()

                        // Player-profile HUD: power level ring + stat tiles.
                        // Tapping pushes the Achievements screen when wired.
                        if let achievementsDestination {
                            NavigationLink {
                                achievementsDestination
                            } label: {
                                ProfileStatsHUDView(state: vm.profile)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ProfileStatsHUDView(state: vm.profile)
                        }

                        // HER-Home — live counts for the user's brain: skills,
                        // jobs, reminders, tasks, insights, projects + active
                        // profile, sourced from GET /v1/dashboard/home.
                        VStack(spacing: 24) {
                            // HER-235 — tapping the section opens the Brain
                            // tab (the knowledge graph). The stats tiles below
                            // stay display-only.
                            Button { onSelectTab("brain") } label: {
                                yourBrainHeader
                            }
                            statsGrid
                        }

                        VStack(spacing: 24) {
                            quickActionsHeader
                            cardGrid
                        }

                        syncAndLearnButton

                        // Extra spacing at bottom for tab bar
                        Spacer().frame(height: 120)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                }
                .refreshable {
                    await vm.refresh()
                }
            }
            .safeAreaInset(edge: .top) {
                LuminaHeader(title: "LuminaVault", onMascotTap: { showQuickSettings = true })
            }
            .sheet(isPresented: $showQuickSettings) {
                QuickSettingsView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .lvBackground()
            .onReceive(NotificationCenter.default.publisher(for: BackendModeStore.modeChangedNotification)) { _ in
                Task { await vm.refresh() }
            }
            .task {
                await vm.refresh()
            }
        }
        .buttonStyle(.plain)
    }

    private var quickActionsHeader: some View {
        sectionHeader("Quick Actions")
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .shadow(color: palette.glowPrimary.opacity(0.3), radius: 4)
            Spacer()
        }
    }

    // HER-235 — "Your Brain" header doubles as the entry point to the Brain
    // tab (knowledge graph). The chevron + brain glyph signal it's tappable.
    private var yourBrainHeader: some View {
        HStack(spacing: 10) {
            LVIconView(.brain, size: 22, tint: palette.primary)
            Text("Your Brain")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .shadow(color: palette.glowPrimary.opacity(0.3), radius: 4)
            Spacer()
            LVIconView(.chevronRight, size: 15, tint: palette.textSecondary)
        }
        .contentShape(Rectangle())
    }

    // HER-Home — seven count tiles. Counts come from `vm.home`; the Insights
    // tile prefers month-to-date token usage from `vm.usage`. Tiles are
    // display-only until detail screens land.
    private var statsGrid: some View {
        let home = vm.home.value
        return LazyVGrid(columns: columns, spacing: 16) {
            SciFiCardView(icon: .brainHeadProfile, title: "Skills", subtitle: count(home?.skillsCount))
            SciFiCardView(icon: .briefcase, title: "Jobs", subtitle: count(home?.jobsCount))
            SciFiCardView(icon: .heartWinged, title: "Reminders", subtitle: count(home?.remindersCount))
            SciFiCardView(icon: .scrollWinged, title: "Tasks", subtitle: count(home?.todosCount))
            SciFiCardView(icon: .sparklesRectangleStack, title: "Projects", subtitle: count(home?.projectsCount))
            SciFiCardView(icon: .lightbulbFill, title: "Insights", subtitle: insightsSubtitle)
            SciFiCardView(icon: .tabSettings, title: "Profile", subtitle: home?.activeProfileName ?? "—")
        }
    }

    private func count(_ value: Int?) -> String {
        value.map(String.init) ?? "—"
    }

    /// Insights tile shows total month-to-date LLM tokens when usage has
    /// loaded; otherwise the count of active findings from the home summary.
    private var insightsSubtitle: String {
        if let usage = vm.usage.value {
            let total = usage.llmTokensIn + usage.llmTokensOut
            return "\(total) tok"
        }
        return count(vm.home.value?.insightsCount)
    }

    private var cardGrid: some View {
        // HER-304 — every card ships an LVIcon token that resolves to a
        // Lumina/Icons/* PNG (HER-301) for the brand-glyph look. Only
        // surfaces with a real destination are shown (no "Stocks" stub):
        // Spaces + AI switch tabs; Health/Ideas/Work push their screens.
        LazyVGrid(columns: columns, spacing: 16) {
            // Tab-targeting cards.
            Button { onSelectTab("workspaces") } label: {
                SciFiCardView(icon: .scrollWinged, title: "Spaces", subtitle: "Winged docs")
            }

            Button { onSelectTab("think") } label: {
                SciFiCardView(icon: .brainHeadProfile, title: "AI", subtitle: "Neural brain")
            }

            // Pushed destinations.
            NavigationLink {
                healthDestination ?? sessionsDestination
            } label: {
                SciFiCardView(icon: .heartWinged, title: "Health", subtitle: "Sparklines")
            }

            NavigationLink { insightsDestination } label: {
                SciFiCardView(icon: .lightbulbFill, title: "Ideas", subtitle: "Glowing light")
            }

            NavigationLink { tasksDestination } label: {
                SciFiCardView(icon: .briefcase, title: "Work", subtitle: "Core tasks")
            }
        }
    }

    private var syncAndLearnButton: some View {
        Button {
            Task { await vm.triggerCompile() }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 14) {
                    if vm.compileViewModel.isBusy {
                        ProgressView()
                            .tint(.white)
                    } else {
                        LVIconView(.sparkles, size: 24, tint: .white, weight: .bold)
                            .shadow(color: .white.opacity(0.8), radius: 8)
                    }
                    
                    Text("Sync & Learn")
                        .font(.system(size: 22, weight: .black))
                }
                
                Text("Compile new captures into your memory.")
                    .font(.system(size: 14, weight: .medium))
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
            .background {
                // HER-304 — single cyan→secondary gradient fill (the white
                // inner stroke was removed; cinematic gold ring carries the
                // premium-CTA spec from DESIGN_SYSTEM §13.3).
                RoundedRectangle(cornerRadius: 28)
                    .fill(
                        LinearGradient(
                            colors: [palette.glowPrimary, palette.secondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .lvAuroraGoldRing(cornerRadius: 28)
            .shadow(color: palette.glowPrimary.opacity(0.7), radius: 20)
            .shadow(color: palette.secondary.opacity(0.4), radius: 30)
            .lvGlowPress()
        }
        .padding(.top, 10)
    }
    
}

// MARK: - Mascot hero (HER-304)

/// Large mascot anchor at the top of Home. Sits below `LuminaHeader`
/// and above Quick Actions. Stitch reference puts the mascot here at
/// roughly 200pt with a subtle particle halo (the halo is the parent
/// `lvParticleBackground` underlayer, not painted by this view).
private struct MascotHero: View {
    @Environment(\.lvPalette) private var palette

    var body: some View {
        VStack(spacing: 12) {
            HermieMascotView(state: .idle, size: 200, fallbackImageName: "Lumina/Mascot/hermie-hero")
                .shadow(color: palette.glowPrimary.opacity(0.55), radius: 28)
                .shadow(color: palette.accent.opacity(0.25), radius: 48)
                .accessibilityHidden(true)

            Text("Your second brain is online.")
                .font(LVTypography.callout.font)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.top, 4)
    }
}
