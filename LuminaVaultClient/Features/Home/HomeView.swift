// LuminaVaultClient/LuminaVaultClient/Features/Home/HomeView.swift
//
// Command Center Home — neural brain core, system vitals, command deck,
// power progress, active jobs, and skills. Backed by GET /v1/dashboard/home.

import Combine
import LuminaVaultShared
import SwiftUI

struct HomeView: View {

    @Environment(\.lvPalette) private var palette
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State var vm: HomeViewModel
    let onAskLumina: () -> Void
    /// Switches the root tab selection. Quick-action cards that target a
    /// tab (Spaces, AI) call this instead of pushing a duplicate screen.
    var onSelectTab: (String) -> Void = { _ in }
    let sessionsDestination: () -> AnyView
    let tasksDestination: () -> AnyView
    let insightsDestination: () -> AnyView
    let serverConnectionDestination: () -> AnyView
    var skillsDestination: (() -> AnyView)? = nil
    var todayDestination: (() -> AnyView)? = nil
    var visualSearchDestination: (() -> AnyView)? = nil
    var healthDestination: (() -> AnyView)? = nil
    var achievementsDestination: (() -> AnyView)? = nil
    var projectsDestination: (() -> AnyView)? = nil
    var remindersDestination: (() -> AnyView)? = nil
    var jobsDestination: (() -> AnyView)? = nil
    var kanbanDestination: (() -> AnyView)? = nil
    var analyticsDestination: (() -> AnyView)? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

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

                Color.clear
                    .lvParticleBackground(intensity: .subtle)
                    .frame(maxHeight: 420)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)

                ScrollView {
                    VStack(spacing: 20) {
                        if horizontalSizeClass == .regular {
                            wideHero
                        } else {
                            compactHero
                        }

                        powerStrip

                        if horizontalSizeClass == .regular {
                            HStack(alignment: .top, spacing: 16) {
                                activeJobsSection
                                skillsSection
                            }
                        } else {
                            activeJobsSection
                            skillsSection
                        }

                        syncAndLearnButton

                        Spacer().frame(height: 120)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                }
                .lvTabBarMinimizeOnScroll()
                .refreshable {
                    await vm.refresh()
                }
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

    // MARK: - Hero layouts

    private var compactHero: some View {
        VStack(spacing: 16) {
            CommandCenterHeroView(
                modelName: home?.primaryModel,
                providerName: home?.primaryProvider,
                agentOnline: home?.agentOnline ?? true,
                networkOnline: vm.isOnline,
                onOpenBrain: { onSelectTab("brain") }
            )
            SystemVitalsPanel(
                home: home,
                tokenTotal: tokenTotal,
                isLoading: isHomeLoading
            )
            commandDeck
        }
    }

    private var wideHero: some View {
        HStack(alignment: .top, spacing: 16) {
            SystemVitalsPanel(
                home: home,
                tokenTotal: tokenTotal,
                isLoading: isHomeLoading
            )
            .frame(maxWidth: 280)

            CommandCenterHeroView(
                modelName: home?.primaryModel,
                providerName: home?.primaryProvider,
                agentOnline: home?.agentOnline ?? true,
                networkOnline: vm.isOnline,
                onOpenBrain: { onSelectTab("brain") }
            )
            .frame(maxWidth: .infinity)

            commandDeck
                .frame(maxWidth: 280)
        }
    }

    private var commandDeck: some View {
        CommandDeckPanel {
            Button(action: onAskLumina) {
                CommandDeckRow(title: "Ask Lumina", number: "01")
            }
            Button {
                Task { await vm.triggerCompile() }
            } label: {
                CommandDeckRow(title: "Sync & Learn", number: "02")
            }
            if let skillsDestination {
                NavigationLink { skillsDestination() } label: {
                    CommandDeckRow(title: "Skills", number: "03")
                }
            }
            if let jobsDestination {
                NavigationLink { jobsDestination() } label: {
                    CommandDeckRow(title: "Jobs", number: "04")
                }
            }
            NavigationLink { insightsDestination() } label: {
                CommandDeckRow(title: "Insights", number: "05")
            }
            if let healthDestination {
                NavigationLink { healthDestination() } label: {
                    CommandDeckRow(title: "Health", number: "06")
                }
            } else {
                Button { onSelectTab("workspaces") } label: {
                    CommandDeckRow(title: "Spaces", number: "06")
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var powerStrip: some View {
        let strip = PowerProgressStrip(
            powerLevel: home?.powerLevel ?? vm.profile.value?.powerLevel,
            powerXP: home?.powerXP ?? vm.profile.value?.powerXP,
            isLoading: isHomeLoading && vm.profile.value == nil
        )
        if let achievementsDestination {
            NavigationLink { achievementsDestination() } label: { strip }
        } else {
            strip
        }
    }

    private var activeJobsSection: some View {
        Group {
            if let jobsDestination {
                NavigationLink { jobsDestination() } label: {
                    ActiveJobsPanel(
                        jobs: activeJobs,
                        isLoading: isHomeLoading && activeJobs.isEmpty
                    )
                }
            } else {
                ActiveJobsPanel(
                    jobs: activeJobs,
                    isLoading: isHomeLoading && activeJobs.isEmpty
                )
            }
        }
    }

    private var skillsSection: some View {
        Group {
            if let skillsDestination {
                NavigationLink { skillsDestination() } label: {
                    SkillsPreviewPanel(
                        skills: home?.skills ?? [],
                        skillsCount: home?.skillsCount,
                        isLoading: isHomeLoading
                    )
                }
            } else {
                SkillsPreviewPanel(
                    skills: home?.skills ?? [],
                    skillsCount: home?.skillsCount,
                    isLoading: isHomeLoading
                )
            }
        }
    }

    // MARK: - Sync CTA

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

    // MARK: - Derived state

    private var home: HomeSummaryResponse? { vm.home.value }

    private var isHomeLoading: Bool {
        if case .loading = vm.home { return true }
        return false
    }

    private var activeJobs: [TaskDTO] {
        if let jobs = home?.activeJobs, !jobs.isEmpty { return jobs }
        // Prefer live running/queued from tasks card load when home list is empty.
        return (vm.tasks.value ?? []).filter { $0.state == .running || $0.state == .queued }
    }

    private var tokenTotal: Int? {
        guard let usage = vm.usage.value else { return nil }
        return usage.llmTokensIn + usage.llmTokensOut
    }
}
