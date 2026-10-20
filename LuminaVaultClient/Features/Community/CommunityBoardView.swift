// LuminaVaultClient/LuminaVaultClient/Features/Community/CommunityBoardView.swift
//
// The Community board. Today's AI Daily Post pinned on top, then threads,
// most active first, loading more as the end scrolls into view. Pushed from
// Home's Daily Post row, or presented from the command palette.

import LuminaVaultShared
import SwiftUI

struct CommunityBoardView: View {
    @State private var vm: CommunityBoardViewModel
    @State private var sheet: BoardSheet?
    @State private var reporting: CommunityPostDTO?
    @State private var confirming: CommunityPendingConfirmation?
    @State private var openThread: CommunityThreadRoute?
    @State private var composeAfterProfile = false

    init(vm: CommunityBoardViewModel) {
        _vm = State(initialValue: vm)
    }

    enum BoardSheet: String, Identifiable {
        case compose
        case profile
        var id: String { rawValue }
    }

    var body: some View {
        content
            .navigationTitle("Community")
            .toolbar { toolbar }
            .refreshable { await vm.load() }
            .task { if vm.state == .idle { await vm.load() } }
            .navigationDestination(item: $openThread) { route in
                CommunityThreadView(
                    vm: CommunityThreadViewModel(
                        post: route.post,
                        client: vm.client,
                        canReply: vm.composeAccess == .allowed
                    ),
                    onBlocked: { vm.removeAuthor($0) },
                    onDeleted: { vm.removePost($0) }
                )
            }
            .sheet(item: $sheet, onDismiss: presentComposerIfReady) { sheet in
                switch sheet {
                case .compose:
                    CommunityComposerSheet { title, body in
                        try await vm.createThread(title: title, body: body)
                    }
                case .profile:
                    CommunityProfileSetupSheet(existing: vm.me?.profile) { handle, name in
                        try await vm.saveProfile(handle: handle, displayName: name)
                    }
                }
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
                isPresented: Binding(get: { vm.actionError != nil }, set: { if !$0 { vm.actionError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.actionError ?? "")
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load the board", systemImage: "exclamationmark.bubble")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await vm.load() } }
            }
        case .loaded where !vm.isEnabled:
            ContentUnavailableView(
                "Community is unavailable",
                systemImage: "person.3",
                description: Text("The Community board isn't available right now.")
            )
        case .loaded:
            list
        }
    }

    private var list: some View {
        List {
            if let daily = vm.dailyPost {
                Section {
                    Button { openThread = CommunityThreadRoute(post: daily) } label: {
                        CommunityDailyPostCard(post: daily)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                if vm.threads.isEmpty {
                    Text("No threads yet. Start the first one.")
                        .foregroundStyle(.secondary)
                }
                ForEach(vm.threads) { post in
                    Button { openThread = CommunityThreadRoute(post: post) } label: {
                        CommunityPostRow(post: post)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        CommunityPostActions(
                            post: post,
                            onReport: { reporting = $0 },
                            onBlock: { confirming = .block($0) },
                            onDelete: { confirming = .delete($0) }
                        )
                    }
                    .task { await vm.loadMoreIfNeeded(after: post) }
                }
                if vm.isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } header: {
                Text("Threads")
            } footer: {
                composeFooter
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var composeFooter: some View {
        switch vm.composeAccess {
        case .postingDisabled:
            Text("Posting is paused for everyone right now. You can still read the board.")
        case .suspended(let until):
            Text("Posting is paused on your account until \(until.formatted(date: .abbreviated, time: .shortened)).")
        default:
            EmptyView()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if vm.isEnabled {
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis.circle") {
                    if vm.me?.profile != nil {
                        Button("Community profile", systemImage: "person.crop.circle") { sheet = .profile }
                    }
                    NavigationLink {
                        CommunityBlockedListView(client: vm.client)
                    } label: {
                        Label("Blocked members", systemImage: "hand.raised")
                    }
                    if vm.isModerator {
                        NavigationLink {
                            CommunityModerationQueueView(client: vm.client)
                        } label: {
                            Label("Moderation queue", systemImage: "checkmark.shield")
                        }
                    }
                    Link(destination: Config.termsOfServiceURL) {
                        Label("Community Guidelines", systemImage: "doc.text")
                    }
                    if let mailto = URL(string: "mailto:\(Config.supportEmail)") {
                        Link(destination: mailto) {
                            Label("Contact support", systemImage: "envelope")
                        }
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("New post", systemImage: "square.and.pencil", action: compose)
                    .disabled(!canStartComposing)
            }
        }
    }

    private var canStartComposing: Bool {
        switch vm.composeAccess {
        case .allowed, .needsProfile: true
        default: false
        }
    }

    /// No profile yet: set one up first, then the composer opens by itself.
    private func compose() {
        if vm.composeAccess == .needsProfile {
            composeAfterProfile = true
            sheet = .profile
        } else {
            sheet = .compose
        }
    }

    private func presentComposerIfReady() {
        guard composeAfterProfile else { return }
        composeAfterProfile = false
        if vm.composeAccess == .allowed { sheet = .compose }
    }

    private func confirm(_ pending: CommunityPendingConfirmation) async {
        switch pending {
        case .block(let post):
            guard let profileID = post.author.profileId else { return }
            await vm.block(profileID: profileID)
        case .delete(let post):
            await vm.delete(postID: post.id)
        }
    }
}
