// LuminaVaultClient/LuminaVaultClient/Features/Community/CommunityModerationQueueView.swift
//
// Moderators only (`me.isModerator`): posts that were reported, held pending
// or hidden. Swipe to hide, restore or remove. Profile suspension is left to
// the web/admin tools for now.

import LuminaVaultShared
import SwiftUI

struct CommunityModerationQueueView: View {
    let client: any CommunityClientProtocol

    @State private var items: [CommunityAdminQueueItemDTO] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if !isLoading, items.isEmpty {
                Text("Nothing waiting for review.")
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                row(item)
                    .swipeActions(edge: .trailing) {
                        Button("Remove", role: .destructive) { Task { await decide(item, .remove) } }
                        Button("Hide") { Task { await decide(item, .hide) } }
                            .tint(.orange)
                    }
                    .swipeActions(edge: .leading) {
                        Button("Restore") { Task { await decide(item, .restore) } }
                            .tint(.green)
                    }
            }
        }
        .navigationTitle("Moderation")
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

    private func row(_ item: CommunityAdminQueueItemDTO) -> some View {
        VStack(alignment: .leading, spacing: LVSpacing.xs) {
            HStack {
                Text(item.post.status.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                if item.openReports > 0 {
                    Text("\(item.openReports) report\(item.openReports == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let category = item.moderationCategory {
                    Text(category).font(.caption).foregroundStyle(.secondary)
                }
            }
            CommunityByline(post: item.post)
            if let title = item.post.title, !title.isEmpty {
                Text(title).font(.headline)
            }
            Text(item.post.body).font(.subheadline).lineLimit(4)
            if !item.reportReasons.isEmpty {
                Text(item.reportReasons.map(CommunityPresentation.reasonLabel).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, LVSpacing.xs)
    }

    private func load() async {
        defer { isLoading = false }
        do {
            items = try await client.adminQueue().items
        } catch {
            guard !APIError.isBenignCancellation(error) else { return }
            errorMessage = CommunityErrorMessage.text(for: error)
        }
    }

    private func decide(_ item: CommunityAdminQueueItemDTO, _ action: CommunityAdminDecisionAction) async {
        do {
            try await client.adminDecide(postID: item.post.id, CommunityAdminDecisionRequest(action: action))
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = CommunityErrorMessage.text(for: error)
        }
    }
}
