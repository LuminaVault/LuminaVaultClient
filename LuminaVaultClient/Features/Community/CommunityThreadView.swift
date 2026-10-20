// LuminaVaultClient/LuminaVaultClient/Features/Community/CommunityThreadView.swift
//
// A thread: the post, its replies oldest first, and a reply field pinned to
// the bottom. Report / Block / Delete live in the toolbar for the post and in
// each reply's context menu.

import LuminaVaultShared
import SwiftUI

struct CommunityThreadView: View {
    @State private var vm: CommunityThreadViewModel
    /// Tells the board a block or delete happened here, so it agrees.
    private let onBlocked: (UUID) -> Void
    private let onDeleted: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reporting: CommunityPostDTO?
    @State private var confirming: CommunityPendingConfirmation?
    @FocusState private var replyFocused: Bool

    init(
        vm: CommunityThreadViewModel,
        onBlocked: @escaping (UUID) -> Void = { _ in },
        onDeleted: @escaping (UUID) -> Void = { _ in }
    ) {
        _vm = State(initialValue: vm)
        self.onBlocked = onBlocked
        self.onDeleted = onDeleted
    }

    var body: some View {
        List {
            Section {
                rootPost
                    .contextMenu { actions(for: vm.post) }
            }

            Section {
                if vm.replies.isEmpty, !vm.isLoading {
                    Text("No replies yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(vm.replies) { reply in
                    replyRow(reply)
                        .contextMenu { actions(for: reply) }
                        .task { await vm.loadMoreIfNeeded(after: reply) }
                }
                if vm.isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } header: {
                Text(vm.post.replyCount == 1 ? "1 reply" : "\(vm.post.replyCount) replies")
            } footer: {
                supportFooter
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(vm.post.isDailyPost ? "Daily Post" : "Thread")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if CommunityPostActions.hasActions(vm.post) {
                ToolbarItem(placement: .primaryAction) {
                    Menu("More", systemImage: "ellipsis.circle") { actions(for: vm.post) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if vm.canReply { replyBar }
        }
        .overlay {
            if vm.isLoading, vm.replies.isEmpty {
                ProgressView()
            }
        }
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .onChange(of: vm.isClosed) { _, closed in
            if closed { dismiss() }
        }
        .sheet(item: $reporting) { post in
            CommunityReportSheet(post: post) { reason, note in
                try await vm.report(postID: post.id, reason: reason, note: note)
            }
        }
        .confirmationDialog(
            confirming?.title ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { pending in
            Button(pending.actionTitle, role: .destructive) {
                Task { await confirm(pending) }
            }
        } message: { pending in
            Text(pending.message)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Pieces

    private var rootPost: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            CommunityByline(post: vm.post)
            CommunityPostCaptions(post: vm.post)
            if let title = vm.post.title, !title.isEmpty {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            Text(vm.post.body)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, LVSpacing.xs)
    }

    private func replyRow(_ reply: CommunityPostDTO) -> some View {
        VStack(alignment: .leading, spacing: LVSpacing.xs) {
            CommunityByline(post: reply)
            CommunityPostCaptions(post: reply)
            Text(reply.body)
                .font(.subheadline)
                .textSelection(.enabled)
        }
        .padding(.vertical, LVSpacing.xs)
    }

    @ViewBuilder
    private func actions(for post: CommunityPostDTO) -> some View {
        CommunityPostActions(
            post: post,
            onReport: { reporting = $0 },
            onBlock: { confirming = .block($0) },
            onDelete: { confirming = .delete($0) }
        )
    }

    private var supportFooter: some View {
        HStack(spacing: LVSpacing.xs) {
            Text("Something wrong?")
            if let mailto = URL(string: "mailto:\(Config.supportEmail)") {
                Link("Contact support", destination: mailto)
            }
        }
        .font(.footnote)
        .padding(.top, LVSpacing.sm)
    }

    private var replyBar: some View {
        HStack(alignment: .bottom, spacing: LVSpacing.sm) {
            TextField("Write a reply", text: $vm.replyText, axis: .vertical)
                .lineLimit(1...5)
                .focused($replyFocused)
                .padding(.horizontal, LVSpacing.md)
                .padding(.vertical, LVSpacing.sm)
                .background(.thinMaterial, in: .rect(cornerRadius: 18))
            Button {
                Task { await vm.sendReply() }
            } label: {
                if vm.isSending {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                }
            }
            .disabled(!vm.canSend)
            .accessibilityLabel("Send reply")
        }
        .padding(.horizontal, LVSpacing.base)
        .padding(.vertical, LVSpacing.sm)
        .background(.bar)
    }

    private func confirm(_ pending: CommunityPendingConfirmation) async {
        switch pending {
        case .block(let post):
            guard let profileID = post.author.profileId else { return }
            if await vm.block(profileID: profileID) { onBlocked(profileID) }
        case .delete(let post):
            if await vm.delete(post), post.id == vm.post.id { onDeleted(post.id) }
        }
    }
}
