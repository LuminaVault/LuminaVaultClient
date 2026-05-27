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
    /// HER-243 — surfaces demoted from the tab bar in the 5-tab redesign.
    /// Optional so existing call sites (and unit tests) keep compiling
    /// without forcing every variant to wire every destination.
    var skillsDestination: AnyView? = nil
    var todayDestination: AnyView? = nil
    var visualSearchDestination: AnyView? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

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
                
                ScrollView {
                    VStack(spacing: 40) {
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
                LuminaHeader(title: "LuminaVault")
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
        HStack {
            Text("Quick Actions")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .shadow(color: palette.glowPrimary.opacity(0.3), radius: 4)
            Spacer()
        }
    }

    private var cardGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            // Row 1: Spaces, AI, Health
            NavigationLink { workspacesView } label: {
                SciFiCardView(icon: "doc.text.fill", title: "Spaces", subtitle: "Winged docs")
            }
            
            NavigationLink { sessionsDestination } label: {
                SciFiCardView(icon: "brain.head.profile", title: "AI", subtitle: "Neural brain")
            }
            
            NavigationLink { sessionsDestination } label: {
                SciFiCardView(icon: "heart.fill", title: "Health", subtitle: "Winged heart")
            }
            
            // Row 2: Ideas, Stocks, Work
            NavigationLink { insightsDestination } label: {
                SciFiCardView(icon: "lightbulb.fill", title: "Ideas", subtitle: "Glowing light")
            }
            
            NavigationLink { sessionsDestination } label: {
                SciFiCardView(icon: "chart.xyaxis.line", title: "Stocks", subtitle: "Market flow")
            }
            
            NavigationLink { visualSearchDestination ?? AnyView(EmptyView()) } label: {
                SciFiCardView(icon: "briefcase.fill", title: "Work", subtitle: "Core tasks")
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
                        Image(systemName: "sparkles")
                            .font(.system(size: 24, weight: .bold))
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
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(
                            LinearGradient(
                                colors: [palette.glowPrimary, palette.secondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Volumetric highlight
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.6), .clear, .white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
            }
            .shadow(color: palette.glowPrimary.opacity(0.7), radius: 20)
            .shadow(color: palette.secondary.opacity(0.4), radius: 30)
            .lvGlowPress()
        }
        .padding(.top, 10)
    }
    
    // Helper to get Workspaces destination if needed, 
    // though in MainTabView it's already defined as a tab.
    // For the "Spaces" card, we'll just navigate to a placeholder 
    // or the existing sessions for now if not explicitly passed.
    private var workspacesView: AnyView {
        // Ideally we'd pass the spacesDestination but HomeView didn't have it.
        // I'll just use sessionsDestination as a placeholder if it's not provided.
        sessionsDestination
    }
}
