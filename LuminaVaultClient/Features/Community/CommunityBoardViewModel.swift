// LuminaVaultClient/LuminaVaultClient/Features/Community/CommunityBoardViewModel.swift
//
// The board: who I am on it (`/me`), today's AI Daily Post pinned on top,
// then threads, most active first, a page at a time. Moderation actions are
// optimistic — a blocked author's posts leave the list before the server
// answers and come back only if it refuses.

import Foundation
import LuminaVaultShared
import Observation

@Observable
@MainActor
final class CommunityBoardViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var me: CommunityMeDTO?
    private(set) var dailyPost: CommunityPostDTO?
    private(set) var threads: [CommunityPostDTO] = []
    private(set) var nextCursor: String?
    private(set) var state: LoadState = .idle
    private(set) var isLoadingMore = false
    /// A transient failure from an action (block, delete, load more).
    var actionError: String?

    let client: any CommunityClientProtocol
    private let pageSize: Int

    init(client: any CommunityClientProtocol, pageSize: Int = 20) {
        self.client = client
        self.pageSize = pageSize
    }

    var composeAccess: CommunityComposeAccess { CommunityComposeAccess(me: me) }
    var isEnabled: Bool { me?.enabled ?? false }
    var isModerator: Bool { me?.isModerator ?? false }
    var hasMore: Bool { nextCursor != nil }

    // MARK: - Loading

    /// `/me` first: when the board is off there is nothing else to ask for.
    func load() async {
        if threads.isEmpty { state = .loading }
        do {
            let me = try await client.me()
            self.me = me
            guard me.enabled else {
                dailyPost = nil
                threads = []
                nextCursor = nil
                state = .loaded
                return
            }
            async let daily = loadDaily()
            async let page = client.threads(cursor: nil, limit: pageSize)
            let first = try await page
            dailyPost = await daily
            threads = first.items.filter { !isPinnedDaily($0) }
            nextCursor = first.nextCursor
            state = .loaded
        } catch {
            guard !APIError.isBenignCancellation(error) else { return }
            if threads.isEmpty {
                state = .failed(CommunityErrorMessage.text(for: error))
            } else {
                actionError = CommunityErrorMessage.text(for: error)
            }
        }
    }

    /// The Daily Post is a nice-to-have on the board: a failure here must
    /// not take the thread list down with it.
    private func loadDaily() async -> CommunityPostDTO? {
        try? await client.dailyToday()
    }

    /// Load the next page when `post` is the last row on screen.
    func loadMoreIfNeeded(after post: CommunityPostDTO) async {
        guard post.id == threads.last?.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await client.threads(cursor: cursor, limit: pageSize)
            let known = Set(threads.map(\.id))
            threads += page.items.filter { !known.contains($0.id) && !isPinnedDaily($0) }
            nextCursor = page.nextCursor
        } catch {
            guard !APIError.isBenignCancellation(error) else { return }
            actionError = CommunityErrorMessage.text(for: error)
        }
    }

    /// Today's Daily Post is pinned above the list; it should not appear twice.
    private func isPinnedDaily(_ post: CommunityPostDTO) -> Bool {
        post.id == dailyPost?.id
    }

    // MARK: - Profile and posting

    func saveProfile(handle: String, displayName: String) async throws {
        let required = me?.termsVersionRequired ?? 1
        let profile = try await client.upsertProfile(CommunityProfileUpsertRequest(
            handle: handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            acceptTerms: true,
            termsVersion: required
        ))
        if let me {
            self.me = CommunityMeDTO(
                enabled: me.enabled,
                postingEnabled: me.postingEnabled,
                profile: profile,
                termsVersionRequired: me.termsVersionRequired,
                isModerator: me.isModerator
            )
        }
    }

    /// Posts the thread and puts it at the top. A `pending` result is still
    /// shown — to its author only, with the "Awaiting review" badge.
    @discardableResult
    func createThread(title: String, body: String) async throws -> CommunityPostDTO {
        let post = try await client.createThread(CommunityPostCreateRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: body.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        threads.removeAll { $0.id == post.id }
        threads.insert(post, at: 0)
        return post
    }

    // MARK: - Moderation

    /// Removes every post by `profileID` at once, then tells the server.
    /// Restores them if the server refuses.
    func block(profileID: UUID) async {
        let before = threads
        removeAuthor(profileID)
        do {
            try await client.block(CommunityBlockRequest(profileId: profileID))
        } catch {
            threads = before
            actionError = CommunityErrorMessage.text(for: error)
        }
    }

    /// Called when a thread screen blocked someone, so the list agrees.
    func removeAuthor(_ profileID: UUID) {
        threads.removeAll { $0.author.profileId == profileID }
    }

    func report(postID: UUID, reason: CommunityReportReason, note: String?) async throws {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await client.report(
            postID: postID,
            CommunityReportRequest(reason: reason, note: (trimmed?.isEmpty ?? true) ? nil : trimmed)
        )
    }

    func delete(postID: UUID) async {
        let before = threads
        removePost(postID)
        do {
            try await client.deletePost(id: postID)
        } catch {
            threads = before
            actionError = CommunityErrorMessage.text(for: error)
        }
    }

    /// Called when a thread screen deleted its root post.
    func removePost(_ postID: UUID) {
        threads.removeAll { $0.id == postID }
    }
}
