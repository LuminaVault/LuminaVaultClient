// LuminaVaultClient/LuminaVaultClient/Features/Think/ThinkWithLuminaView.swift
// HER-37: root of the "Think" tab.
//
// Layout: Ask Lumina input bar at the top, suggestion chips below it,
// then either the empty state, a thinking spinner, an insight card, or
// an error. Toolbar links to Lumina's Notebook (memo list).
import SwiftUI

struct ThinkWithLuminaView: View {
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

                    if !vm.suggestions.isEmpty && !isInsightActive {
                        SuggestionChipsRow(suggestions: vm.suggestions) { suggestion in
                            vm.applySuggestion(suggestion)
                            Task { await vm.ask() }
                        }
                    }

                    HermieMascotView(state: vm.mascotState, size: 140, fallbackImageName: "OnboardingMascot")
                        .padding(.top, 4)

                    phaseContent
                        .padding(.horizontal, 16)
                }
                .padding(.vertical, 16)
            }
            .lvBackground()
            .navigationTitle("Think with Lumina")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MemoListView(vm: MemoListViewModel(client: memoClient))
                    } label: {
                        Image(systemName: "book.closed.fill")
                            .foregroundStyle(Color.lvAmber)
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
                .tint(Color.lvCyan)
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

    private var placeholderView: some View {
        VStack(spacing: 8) {
            Text("What's on your mind?")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.lvTextPrimary)
            Text("Ask anything. Lumina will pull from your vault and recent learnings.")
                .font(.system(size: 13))
                .foregroundStyle(Color.lvTextSub)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private var isInsightActive: Bool {
        if case .insight = vm.phase { return true }
        return false
    }
}

extension MemoRequest: @retroactive Identifiable {
    public var id: String { topic }
}
