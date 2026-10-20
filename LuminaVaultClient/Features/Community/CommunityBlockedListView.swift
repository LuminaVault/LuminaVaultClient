// LuminaVaultClient/LuminaVaultClient/Features/Community/CommunityBlockedListView.swift
//
// Members you blocked, with a way back. Unblocking is immediate; their posts
// reappear on the next board refresh.

import LuminaVaultShared
import SwiftUI

struct CommunityBlockedListView: View {
    let client: any CommunityClientProtocol

    @State private var items: [CommunityBlockedProfileDTO] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if !isLoading, items.isEmpty {
                Text("You haven't blocked anyone.")
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName).font(.body.weight(.semibold))
                    Text("@\(item.handle)").font(.subheadline).foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("Unblock") { Task { await unblock(item) } }
                        .tint(.blue)
                }
            }
        }
        .navigationTitle("Blocked members")
        .overlay { if isLoading { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            items = try await client.blocks().items
        } catch {
            guard !APIError.isBenignCancellation(error) else { return }
            errorMessage = CommunityErrorMessage.text(for: error)
        }
    }

    private func unblock(_ item: CommunityBlockedProfileDTO) async {
        let before = items
        items.removeAll { $0.id == item.id }
        do {
            try await client.unblock(profileID: item.profileId)
        } catch {
            items = before
            errorMessage = CommunityErrorMessage.text(for: error)
        }
    }
}
