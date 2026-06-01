// LuminaVaultClient/LuminaVaultClient/Features/Achievements/AchievementsView.swift
//
// The Achievements screen. Pushed from the Home profile HUD. Renders the four
// RPG "Forms" (server archetypes) as badge grids, a recent-unlocks strip, and
// presents the celebration overlay for any freshly-unlocked badges.

import LuminaVaultShared
import SwiftUI

struct AchievementsView: View {
    @Environment(\.lvPalette) private var palette

    @State var vm: AchievementsViewModel

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(spacing: LVSpacing.xl) {
                    header
                    content
                }
                .padding(.horizontal, LVSpacing.base)
                .padding(.bottom, LVSpacing.hero)
            }
        }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.refresh() }
        .fullScreenCover(isPresented: celebrationBinding) {
            AchievementUnlockOverlay(subs: vm.pendingCelebrations) {
                vm.dismissCelebrations()
            }
            .environment(\.lvPalette, palette)
        }
    }

    private var celebrationBinding: Binding<Bool> {
        Binding(
            get: { !vm.pendingCelebrations.isEmpty },
            set: { if !$0 { vm.dismissCelebrations() } }
        )
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            RadialGradient(
                colors: [palette.glowPrimary.opacity(0.12), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 500
            ).ignoresSafeArea()
            RadialGradient(
                colors: [palette.accent.opacity(0.08), .clear],
                center: .bottomLeading, startRadius: 0, endRadius: 600
            ).ignoresSafeArea()
            Color.clear
                .lvParticleBackground(intensity: .subtle)
                .frame(maxHeight: 420)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: LVSpacing.md) {
            HermieMascotView(state: .happy, size: 140, fallbackImageName: "Mascot")
                .shadow(color: palette.glowPrimary.opacity(0.5), radius: 22)
            if let total = unlockedSummary {
                Text(total)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.top, LVSpacing.md)
    }

    private var unlockedSummary: String? {
        guard let list = vm.list.value else { return nil }
        let subs = list.archetypes.flatMap(\.sub)
        let unlocked = subs.filter { $0.unlockedAt != nil }.count
        guard !subs.isEmpty else { return nil }
        return "\(unlocked) of \(subs.count) badges unlocked"
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch vm.list {
        case .loading:
            ProgressView()
                .tint(palette.glowPrimary)
                .frame(maxWidth: .infinity, minHeight: 240)
        case .failed(let message):
            failed(message)
        case .loaded(let list):
            recentStrip
            if list.archetypes.allSatisfy({ $0.sub.allSatisfy { $0.unlockedAt == nil } }) {
                emptyState
            }
            ForEach(list.archetypes, id: \.key) { archetype in
                ArchetypeFormCard(archetype: archetype)
            }
        }
    }

    @ViewBuilder
    private var recentStrip: some View {
        if let recent = vm.recent.value, !recent.unlocks.isEmpty {
            VStack(alignment: .leading, spacing: LVSpacing.sm) {
                Text("Recent unlocks")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LVSpacing.md) {
                        ForEach(recent.unlocks, id: \.key) { unlock in
                            recentChip(unlock)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func recentChip(_ unlock: AchievementsRecentResponse.UnlockDTO) -> some View {
        HStack(spacing: LVSpacing.xs) {
            Image(systemName: "sparkles")
                .foregroundStyle(palette.accent)
            Text(unlock.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, LVSpacing.md)
        .padding(.vertical, LVSpacing.sm)
        .background(Capsule().fill(palette.surface))
        .overlay(Capsule().stroke(palette.accent.opacity(0.3), lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: LVSpacing.sm) {
            Text("Your legend begins")
                .font(.title3.weight(.bold))
                .foregroundStyle(palette.textPrimary)
            Text("Capture, compile, and explore your vault to forge your first badge.")
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LVSpacing.lg)
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: LVSpacing.md) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.refresh() } }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.glowPrimary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

#if DEBUG
private struct PreviewAchievementsClient: AchievementsClientProtocol {
    func list() async throws -> AchievementsListResponse {
        let s: (String, Int64, Int64, Bool) -> AchievementsListResponse.SubDTO = { l, t, p, u in
            .init(key: l, label: l, target: t, progress: p, unlockedAt: u ? Date() : nil)
        }
        return AchievementsListResponse(catalogVersion: 1, archetypes: [
            .init(key: "lightbringer", label: "Lightbringer", sub: [
                s("First Spark", 1, 1, true), s("Kindled Mind", 10, 4, false),
                s("Illuminator", 50, 0, false), s("Lightbearer", 200, 0, false)
            ]),
            .init(key: "soulseeker", label: "Soulseeker", sub: [
                s("First Relic", 1, 1, true), s("Collector", 10, 10, true),
                s("Cartographer", 3, 3, true), s("Soulkeeper", 100, 100, true)
            ])
        ])
    }

    func recent(limit: Int) async throws -> AchievementsRecentResponse {
        AchievementsRecentResponse(unlocks: [
            .init(key: "collector", label: "Collector", unlockedAt: Date()),
            .init(key: "first-relic", label: "First Relic", unlockedAt: Date())
        ])
    }
}

#Preview("Achievements") {
    NavigationStack {
        AchievementsView(vm: AchievementsViewModel(client: PreviewAchievementsClient()))
    }
    .environment(\.lvPalette, .cyanGoldDark)
}
#endif
