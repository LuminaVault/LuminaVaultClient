// LuminaVaultClient/LuminaVaultClient/Features/Think/ThinkWithLuminaView.swift
// HER-37: root of the "Think" tab.
//
// Layout: Ask Lumina input bar at the top, suggestion chips below it,
// then either the empty state, a thinking spinner, an insight card, or
// an error. Toolbar links to Lumina's Notebook (memo list).
import SwiftUI

struct ThinkWithLuminaView: View {

    @Environment(\.lvPalette) private var palette

    @State var vm: ThinkWithLuminaViewModel
    let memoClient: MemoClientProtocol

    @State private var pendingMemoSeed: MemoRequest?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AskLuminaInputView(
                        text: Binding(get: { vm.queryText }, set: { vm.queryText = $0 }),
                        isBusy: vm.isBusy,
                    ) {
                        Task { await vm.ask() }
                    }
                    .padding(.horizontal, 16)

                    if !vm.suggestions.isEmpty && !isInsightActive && !isEmptyPhase {
                        SuggestionChipsRow(suggestions: vm.suggestions) { suggestion in
                            vm.applySuggestion(suggestion)
                            Task { await vm.ask() }
                        }
                    }

                    // HER-255 — only render the standalone mascot when there is
                    // an active phase; the empty state has its own mascot baked
                    // into LVEmptyState.
                    if !isEmptyPhase {
                        HermieMascotView(state: vm.mascotState, size: 140, fallbackImageName: "OnboardingMascot")
                            .padding(.top, 4)
                    }

                    phaseContent
                        .padding(.horizontal, 16)
                }
                .padding(.vertical, 16)
            }
            .lvBackground()
            .navigationTitle("Think with Lumina")
            .navigationBarTitleDisplayMode(.inline)
            .lvNavBrand(position: .topLeading)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MemoListView(vm: MemoListViewModel(client: memoClient))
                    } label: {
                        Image(systemName: "book.closed.fill")
                            .foregroundStyle(palette.accent)
                    }
                }
            }
            .task { await vm.loadSuggestions() }
            .sheet(item: $pendingMemoSeed) { seed in
                MemoEditorView(vm: MemoEditorViewModel(client: memoClient, seed: seed))
            }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch vm.phase {
        case .empty:
            placeholderView
        case .querying:
            ProgressView("Thinking…")
                .progressViewStyle(.circular)
                .tint(palette.primary)
                .padding(.top, 24)
        case let .insight(response, queryText):
            InsightCardView(
                response: response,
                queryText: queryText,
                followUps: vm.followUps,
                onSaveAsMemo: { pendingMemoSeed = vm.memoSeed() },
                onFollowUp: { chip in
                    vm.tapFollowUp(chip)
                    Task { await vm.ask() }
                },
            )
        case let .failed(message):
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.top, 24)
        }
    }

    // HER-255 — dramatic empty state per the issue: mascot front and centre
    // with a neural particle ring, plus the suggestion chips folded into the
    // empty surface as floating "holographic" prompts.
    private var placeholderView: some View {
        LVEmptyState(
            mascot: .thinking,
            headline: "What would you like to explore today?",
            supporting: "Ask anything. Lumina will pull from your vault and recent learnings.",
            primaryCTA: nil,
            chips: vm.suggestions.prefix(4).map { suggestion in
                LVEmptyStateChip(label: suggestion) {
                    vm.applySuggestion(suggestion)
                    Task { await vm.ask() }
                }
            }
        )
    }

    private var isInsightActive: Bool {
        if case .insight = vm.phase { return true }
        return false
    }

    private var isEmptyPhase: Bool {
        if case .empty = vm.phase { return true }
        return false
    }
}

extension MemoRequest: @retroactive Identifiable {
    public var id: String { topic }
}
