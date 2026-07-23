// LuminaVaultClient/LuminaVaultClient/Features/Reflect/ReflectTabView.swift
//
// HER-194 — primary "Reflect" tab. Mascot header, three skill cards
// (Patterns / Contradictions / Beliefs), recent-reflections feed.
// The same sheet swaps between TopicInputSheet (gather topic) and
// ReflectionResultView (run + result + Save) based on runner state, so
// the user perceives a single uninterrupted flow.

import LuminaVaultShared
import SwiftUI

struct ReflectTabView: View {
    @Environment(\.lvPalette) private var palette

    @State var vm: ReflectViewModel
    @State var runner: ReflectionRunner

    let vaultClient: VaultClientProtocol
    let memoryClient: MemoryClientProtocol

    /// Drives the modal sheet. Two stages with the same skill share an
    /// identity so SwiftUI swaps content in-place without dismissing.
    @State private var activeSkill: ReflectionSkill?
    @State private var stage: Stage = .input
    @State private var pendingTopic: String?

    private enum Stage { case input, result }

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    header
                    cardsGrid
                    Divider()
                        .background(palette.surfaceStroke)
                        .padding(.horizontal, 20)
                    feed
                }
                .padding(.vertical, 20)
            }
            .lvTabBarMinimizeOnScroll()
            .refreshable { await vm.refreshRecent() }
        }
        .lvBackground()
        .task { await vm.refreshRecent() }
        .sheet(item: $activeSkill, onDismiss: resetModal) { skill in
            modalContent(for: skill)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 6) {
            HermieMascotView(
                state: tabMascotState,
                size: 110,
                fallbackImageName: "OnboardingMascot",
            )
            Text("Reflect")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(
                    LinearGradient(
                        colors: [palette.accent, palette.primary],
                        startPoint: .leading,
                        endPoint: .trailing,
                    ),
                )
        }
        .padding(.top, 12)
    }

    private var cardsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ReflectSkillCard(skill: .patterns) { present(.patterns) }
                ReflectSkillCard(skill: .contradictions) { present(.contradictions) }
            }
            ReflectSkillCard(skill: .beliefs) { present(.beliefs) }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var feed: some View {
        switch vm.feedState {
        case .loading:
            ProgressView().tint(palette.primary).padding()
        case .loaded:
            SavedReflectionsListView(
                files: vm.recentFiles,
                vaultClient: vaultClient,
                memoryClient: memoryClient,
            )
        case .failed(let message):
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.lvTextMuted)
                .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func modalContent(for skill: ReflectionSkill) -> some View {
        switch stage {
        case .input:
            TopicInputSheet(skill: skill) { topic in
                pendingTopic = topic
                stage = .result
                Task { await runner.run(skill: skill, topic: topic) }
            }
        case .result:
            ReflectionResultView(
                skill: skill,
                topic: pendingTopic,
                runner: runner,
                vaultClient: vaultClient,
                memoryClient: memoryClient,
                onSaved: { Task { await vm.refreshRecent() } },
            )
        }
    }

    // MARK: - State

    private var tabMascotState: HermieMascotState {
        switch runner.state {
        case .running, .saving: .thinking
        case .result, .saved: .celebrating
        case .failed, .idle: .idle
        }
    }

    private func present(_ skill: ReflectionSkill) {
        stage = .input
        pendingTopic = nil
        runner.reset()
        activeSkill = skill
    }

    private func resetModal() {
        stage = .input
        pendingTopic = nil
        runner.reset()
    }
}
