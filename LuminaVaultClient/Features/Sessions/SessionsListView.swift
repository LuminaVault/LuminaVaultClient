// LuminaVaultClient/LuminaVaultClient/Features/Sessions/SessionsListView.swift
//
// HER-245 — Sessions list. Pushed from Home dashboard. Empty until
// session persistence lands server-side.

import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class SessionsListViewModel {
    enum LoadState: Equatable { case loading, loaded, failed(String) }
    var state: LoadState = .loading
    var sessions: [SessionDTO] = []
    /// HER-261 — when set, list calls scope to this workspace (Space).
    /// `nil` shows all workspaces.
    var workspaceID: UUID?
    private let client: SessionsClientProtocol

    init(client: SessionsClientProtocol, workspaceID: UUID? = nil) {
        self.client = client
        self.workspaceID = workspaceID
    }

    func load() async {
        state = .loading
        do {
            let response = try await client.list(limit: 50, workspaceID: workspaceID)
            sessions = response.sessions.sorted { $0.lastMessageAt > $1.lastMessageAt }
            state = .loaded
        } catch {
            state = .failed("Couldn't load sessions.")
        }
    }

    func setWorkspace(_ id: UUID?) async {
        workspaceID = id
        await load()
    }
}

struct SessionsListView: View {
    @State var vm: SessionsListViewModel
    @Environment(WorkspaceSelection.self) private var workspaceSelection

    var body: some View {
        ZStack {
            Color.lvNavy.ignoresSafeArea()
            content
        }
        .navigationTitle("Sessions")
        .lvBackground()
        .task {
            // HER-261 — react to active-workspace flips from the global
            // selection without leaking it into the VM constructor.
            await vm.setWorkspace(workspaceSelection.activeWorkspaceID)
        }
        .onChange(of: workspaceSelection.activeWorkspaceID) { _, newID in
            Task { await vm.setWorkspace(newID) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().tint(.lvCyan)
        case .failed(let message):
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.lvTextMuted)
                .padding()
        case .loaded where vm.sessions.isEmpty:
            emptyState
        case .loaded:
            List {
                ForEach(vm.sessions) { session in
                    row(session)
                        .listRowBackground(Color.lvNavy.opacity(0.5))
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ session: SessionDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.lvTextPrimary)
                Spacer()
                Text("\(session.messageCount) msg")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.lvTextMuted)
            }
            Text(session.preview)
                .font(.system(size: 12))
                .foregroundStyle(Color.lvTextSub)
                .lineLimit(2)
            Text(Self.formatter.localizedString(for: session.lastMessageAt, relativeTo: Date()))
                .font(.system(size: 10))
                .foregroundStyle(Color.lvTextMuted)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No sessions yet.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.lvTextPrimary)
            Text("Start a chat from Think to see it here.")
                .font(.system(size: 12))
                .foregroundStyle(Color.lvTextSub)
        }
        .multilineTextAlignment(.center)
        .padding(.top, 40)
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
