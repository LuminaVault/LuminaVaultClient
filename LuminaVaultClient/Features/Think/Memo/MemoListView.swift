// LuminaVaultClient/LuminaVaultClient/Features/Think/Memo/MemoListView.swift
// HER-37: Lumina's Notebook — the saved memos surface. Reached from
// ThinkWithLuminaView toolbar.
import SwiftUI

struct MemoListView: View {

    @Environment(\.lvPalette) private var palette

    @State var vm: MemoListViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                switch vm.phase {
                case .loading:
                    ProgressView()
                        .padding(.top, 60)
                case let .failed(message):
                    VStack(spacing: 6) {
                        Text("Couldn't load memos")
                            .font(.system(size: 14, weight: .semibold))
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 60)
                case .loaded(let memos) where memos.isEmpty:
                    emptyState
                case .loaded(let memos):
                    ForEach(memos) { memo in
                        MemoRowView(memo: memo)
                    }
                }
            }
            .padding(16)
        }
        .lvBackground()
        .navigationTitle("Lumina's Notebook")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bookmark")
                .font(.system(size: 32))
                .foregroundStyle(palette.accent.opacity(0.6))
            Text("No memos yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text("Save an insight from \"Think with Lumina\" and it will land here.")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 80)
        .padding(.horizontal, 24)
    }
}
