// LuminaVaultClient/LuminaVaultClient/Features/Community/CommunityThreadViewModel.swift
//
// One thread: the root post, its replies oldest first a page at a time, and a
// reply composer. Deleting or blocking the root's author ends the thread for
// this viewer, which the view answers by popping back to the board.

import Foundation
import LuminaVaultShared
import Observation

@Observable
@MainActor
final class CommunityThreadViewModel {
    private(set) var post: CommunityPostDTO
    private(set) var replies: [CommunityPostDTO] = []
    private(set) var nextCursor: String?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isSending = false
    /// Set once the root post is gone for this viewer (deleted or blocked).
    private(set) var isClosed = false
    var replyText = ""
    var errorMessage: String?

    private let client: any CommunityClientProtocol
    private let pageSize: Int
    let canReply: Bool

    init(post: CommunityPostDTO, client: any CommunityClientProtocol, canReply: Bool, pageSize: Int = 20) {
        self.post = post
        self.client = client
        self.canReply = canReply
        self.pageSize = pageSize
    }

    var hasMore: Bool { nextCursor != nil }

    var canSend: Bool {
        canReply && !isSending && !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let root = client.post(id: post.id)
            async let page = client.replies(postID: post.id, cursor: nil, limit: pageSize)
            let (fresh, first) = try await (root, page)
            post = fresh
            replies = first.items
            nextCursor = first.nextCursor
        } catch {
            guard !APIError.isBenignCancellation(error) else { return }
            if CommunityErrorMessage.code(for: error) == "post_not_found" { isClosed = true }
            errorMessage = CommunityErrorMessage.text(for: error)
        }
    }

    func loadMoreIfNeeded(after reply: CommunityPostDTO) async {
        guard reply.id == replies.last?.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await client.replies(postID: post.id, cursor: cursor, limit: pageSize)
            let known = Set(replies.map(\.id))
            replies += page.items.filter { !known.contains($0.id) }
            nextCursor = page.nextCursor
        } catch {
            guard !APIError.isBenignCancellation(error) else { return }
            errorMessage = CommunityErrorMessage.text(for: error)
        }
    }

    func sendReply() async {
        guard canSend else { return }
        isSending = true
        defer { isSending = false }
        do {
            let reply = try await client.createReply(
                postID: post.id,
                CommunityReplyCreateRequest(body: replyText.trimmingCharacters(in: .whitespacesAndNewlines))
            )
            replyText = ""
            // Oldest first: a new reply belongs at the end — but only once the
            // end is on screen, or the next page would bring it in twice.
            if nextCursor == nil { replies.append(reply) }
        } catch {
            errorMessage = CommunityErrorMessage.text(for: error)
        }
    }

    // MARK: - Moderation

    /// Returns true when the server accepted the delete.
    @discardableResult
    func delete(_ target: CommunityPostDTO) async -> Bool {
        let before = replies
        if target.id == post.id {
            isClosed = true
        } else {
            replies.removeAll { $0.id == target.id }
        }
        do {
            try await client.deletePost(id: target.id)
            return true
        } catch {
            replies = before
            if target.id == post.id { isClosed = false }
            errorMessage = CommunityErrorMessage.text(for: error)
            return false
        }
    }

    /// Hides everything `profileID` wrote here at once; closes the thread if
    /// they wrote the root. Returns true when the server accepted the block.
    @discardableResult
    func block(profileID: UUID) async -> Bool {
        let before = replies
        replies.removeAll { $0.author.profileId == profileID }
        let closesThread = post.author.profileId == profileID
        if closesThread { isClosed = true }
        do {
            try await client.block(CommunityBlockRequest(profileId: profileID))
            return true
        } catch {
            replies = before
            if closesThread { isClosed = false }
            errorMessage = CommunityErrorMessage.text(for: error)
            return false
        }
    }

    func report(postID: UUID, reason: CommunityReportReason, note: String?) async throws {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await client.report(
            postID: postID,
            CommunityReportRequest(reason: reason, note: (trimmed?.isEmpty ?? true) ? nil : trimmed)
        )
    }
}
