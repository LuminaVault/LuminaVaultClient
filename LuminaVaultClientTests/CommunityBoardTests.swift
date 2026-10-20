// LuminaVaultClient/LuminaVaultClientTests/CommunityBoardTests.swift
//
// Community board: pagination accumulates and stops at a nil cursor, a block
// removes the author's posts before the server answers, report sends what was
// chosen, moderation 422s read as the guidelines sentence, the pending badge
// is author-only, and a 204 Daily Post is nil. Stub client, no network.

import Foundation
import LuminaVaultShared
import XCTest

@testable import LuminaVaultClient

@MainActor
final class StubCommunityClient: CommunityClientProtocol {
    var meResult: Result<CommunityMeDTO, Error> = .success(CommunityFixtures.me())
    var pages: [String?: CommunityPostPageDTO] = [:]
    var dailyResult: Result<CommunityPostDTO?, Error> = .success(nil)
    var blockError: Error?
    var createResult: Result<CommunityPostDTO, Error>?
    private(set) var threadCursors: [String?] = []
    private(set) var blocked: [UUID] = []
    private(set) var reports: [(UUID, CommunityReportRequest)] = []
    private(set) var deleted: [UUID] = []
    /// Lets a test look at the list while `block` is still in flight.
    var onBlock: (() -> Void)?

    func me() async throws -> CommunityMeDTO { try meResult.get() }
    func upsertProfile(_ request: CommunityProfileUpsertRequest) async throws -> CommunityProfileDTO {
        CommunityFixtures.profile(handle: request.handle)
    }
    func threads(cursor: String?, limit _: Int) async throws -> CommunityPostPageDTO {
        threadCursors.append(cursor)
        return pages[cursor] ?? CommunityPostPageDTO(items: [], nextCursor: nil)
    }
    func createThread(_ request: CommunityPostCreateRequest) async throws -> CommunityPostDTO {
        if let createResult { return try createResult.get() }
        return CommunityFixtures.post(title: request.title, isOwn: true)
    }
    func post(id: UUID) async throws -> CommunityPostDTO { CommunityFixtures.post(id: id) }
    func replies(postID _: UUID, cursor _: String?, limit _: Int) async throws -> CommunityPostPageDTO {
        CommunityPostPageDTO(items: [], nextCursor: nil)
    }
    func createReply(postID: UUID, _ request: CommunityReplyCreateRequest) async throws -> CommunityPostDTO {
        CommunityFixtures.post(parentID: postID, body: request.body, isOwn: true)
    }
    func deletePost(id: UUID) async throws { deleted.append(id) }
    func report(postID: UUID, _ request: CommunityReportRequest) async throws { reports.append((postID, request)) }
    func dailyToday() async throws -> CommunityPostDTO? { try dailyResult.get() }
    func blocks() async throws -> CommunityBlockListDTO { CommunityBlockListDTO(items: []) }
    func block(_ request: CommunityBlockRequest) async throws {
        onBlock?()
        blocked.append(request.profileId)
        if let blockError { throw blockError }
    }
    func unblock(profileID _: UUID) async throws {}
    func adminQueue() async throws -> CommunityAdminQueueDTO { CommunityAdminQueueDTO(items: []) }
    func adminDecide(postID _: UUID, _: CommunityAdminDecisionRequest) async throws {}
}

enum CommunityFixtures {
    static func profile(handle: String = "ana", termsVersion: Int = 1, suspendedUntil: Date? = nil) -> CommunityProfileDTO {
        CommunityProfileDTO(
            id: UUID(), handle: handle, displayName: "Ana", termsVersion: termsVersion,
            termsAcceptedAt: .now, postingSuspendedUntil: suspendedUntil
        )
    }

    static func me(
        enabled: Bool = true,
        postingEnabled: Bool = true,
        profile: CommunityProfileDTO? = profile(),
        termsVersionRequired: Int = 1
    ) -> CommunityMeDTO {
        CommunityMeDTO(
            enabled: enabled, postingEnabled: postingEnabled, profile: profile,
            termsVersionRequired: termsVersionRequired, isModerator: false
        )
    }

    static func post(
        id: UUID = UUID(),
        parentID: UUID? = nil,
        title: String? = "Hello",
        body: String = "Body",
        author: UUID? = UUID(),
        kind: CommunityAuthorKind = .user,
        isDailyPost: Bool = false,
        aiLabel: String? = nil,
        status: CommunityPostStatus = .visible,
        isOwn: Bool = false
    ) -> CommunityPostDTO {
        CommunityPostDTO(
            id: id, parentId: parentID, title: title, body: body,
            author: CommunityAuthorDTO(
                kind: kind,
                profileId: kind == .ai ? nil : author,
                handle: kind == .ai ? nil : "member",
                displayName: kind == .ai ? nil : "Member"
            ),
            isDailyPost: isDailyPost, aiLabel: aiLabel, status: status,
            isOwn: isOwn, createdAt: .now, lastActivityAt: .now
        )
    }

    static func structured(_ status: Int, _ message: String) -> APIError {
        .httpError(statusCode: status, data: Data(#"{"error":{"message":"\#(message)"}}"#.utf8))
    }
}

@MainActor
final class CommunityBoardViewModelTests: XCTestCase {
    private func run(_ body: @escaping @MainActor () async -> Void) {
        let exp = expectation(description: "async")
        Task { @MainActor in
            await body()
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
    }

    func testPaginationAccumulatesAndStopsAtNilCursor() {
        let client = StubCommunityClient()
        let a = CommunityFixtures.post(), b = CommunityFixtures.post(), c = CommunityFixtures.post()
        client.pages = [
            nil: CommunityPostPageDTO(items: [a, b], nextCursor: "p2"),
            "p2": CommunityPostPageDTO(items: [c], nextCursor: nil),
        ]
        let sut = CommunityBoardViewModel(client: client, pageSize: 2)

        run { await sut.load() }
        XCTAssertEqual(sut.threads.map(\.id), [a.id, b.id])
        XCTAssertTrue(sut.hasMore)

        // Only the last row on screen asks for more.
        run { await sut.loadMoreIfNeeded(after: a) }
        XCTAssertEqual(client.threadCursors, [nil])

        run { await sut.loadMoreIfNeeded(after: b) }
        XCTAssertEqual(sut.threads.map(\.id), [a.id, b.id, c.id])
        XCTAssertFalse(sut.hasMore)

        run { await sut.loadMore() }
        XCTAssertEqual(client.threadCursors, [nil, "p2"], "no request once the cursor is nil")
    }

    func testDisabledBoardLoadsNothingElse() {
        let client = StubCommunityClient()
        client.meResult = .success(CommunityFixtures.me(enabled: false))
        let sut = CommunityBoardViewModel(client: client)
        run { await sut.load() }
        XCTAssertFalse(sut.isEnabled)
        XCTAssertTrue(client.threadCursors.isEmpty)
        XCTAssertEqual(sut.composeAccess, .boardDisabled)
    }

    func testDailyPostIsPinnedNotRepeatedInList() {
        let client = StubCommunityClient()
        let daily = CommunityFixtures.post(kind: .ai, isDailyPost: true, aiLabel: "AI-generated · Daily Post")
        let other = CommunityFixtures.post()
        client.dailyResult = .success(daily)
        client.pages = [nil: CommunityPostPageDTO(items: [daily, other], nextCursor: nil)]
        let sut = CommunityBoardViewModel(client: client)
        run { await sut.load() }
        XCTAssertEqual(sut.dailyPost?.id, daily.id)
        XCTAssertEqual(sut.threads.map(\.id), [other.id])
    }

    func testBlockRemovesAuthorsPostsOptimistically() {
        let client = StubCommunityClient()
        let blockedAuthor = UUID()
        let p1 = CommunityFixtures.post(author: blockedAuthor)
        let p2 = CommunityFixtures.post()
        let p3 = CommunityFixtures.post(author: blockedAuthor)
        client.pages = [nil: CommunityPostPageDTO(items: [p1, p2, p3], nextCursor: nil)]
        let sut = CommunityBoardViewModel(client: client)
        run { await sut.load() }

        var seenDuringRequest: [UUID] = []
        client.onBlock = { seenDuringRequest = sut.threads.map(\.id) }
        run { await sut.block(profileID: blockedAuthor) }

        XCTAssertEqual(seenDuringRequest, [p2.id], "gone before the server answered")
        XCTAssertEqual(sut.threads.map(\.id), [p2.id])
        XCTAssertEqual(client.blocked, [blockedAuthor])
    }

    func testBlockFailureRestoresPosts() {
        let client = StubCommunityClient()
        let author = UUID()
        let p1 = CommunityFixtures.post(author: author)
        client.pages = [nil: CommunityPostPageDTO(items: [p1], nextCursor: nil)]
        client.blockError = CommunityFixtures.structured(400, "cannot_block_self")
        let sut = CommunityBoardViewModel(client: client)
        run { await sut.load() }
        run { await sut.block(profileID: author) }
        XCTAssertEqual(sut.threads.map(\.id), [p1.id])
        XCTAssertEqual(sut.actionError, "You can't block yourself.")
    }

    func testReportSendsReasonAndTrimmedNote() {
        let client = StubCommunityClient()
        let sut = CommunityBoardViewModel(client: client)
        let postID = UUID()
        run { try? await sut.report(postID: postID, reason: .harassment, note: "  rude  ") }
        run { try? await sut.report(postID: postID, reason: .spam, note: "   ") }
        XCTAssertEqual(client.reports.count, 2)
        XCTAssertEqual(client.reports[0].0, postID)
        XCTAssertEqual(client.reports[0].1, CommunityReportRequest(reason: .harassment, note: "rude"))
        XCTAssertEqual(client.reports[1].1, CommunityReportRequest(reason: .spam, note: nil))
    }

    func testCreatedPendingThreadGoesOnTopWithBadge() {
        let client = StubCommunityClient()
        let pending = CommunityFixtures.post(status: .pending, isOwn: true)
        client.createResult = .success(pending)
        client.pages = [nil: CommunityPostPageDTO(items: [CommunityFixtures.post()], nextCursor: nil)]
        let sut = CommunityBoardViewModel(client: client)
        run { await sut.load() }
        run { _ = try? await sut.createThread(title: "Hi there", body: "Body") }
        XCTAssertEqual(sut.threads.first?.id, pending.id)
        XCTAssertTrue(CommunityPresentation.showsPendingBadge(sut.threads[0]))
    }
}

@MainActor
final class CommunityPresentationTests: XCTestCase {
    func testPendingBadgeIsForTheAuthorOnly() {
        XCTAssertTrue(CommunityPresentation.showsPendingBadge(CommunityFixtures.post(status: .pending, isOwn: true)))
        XCTAssertFalse(CommunityPresentation.showsPendingBadge(CommunityFixtures.post(status: .pending, isOwn: false)))
        XCTAssertFalse(CommunityPresentation.showsPendingBadge(CommunityFixtures.post(status: .visible, isOwn: true)))
    }

    func testModerationRejectedReadsAsGuidelines() {
        let error = CommunityFixtures.structured(422, "moderation_rejected:harassment")
        XCTAssertEqual(CommunityErrorMessage.text(for: error), CommunityErrorMessage.guidelines)
        XCTAssertTrue(CommunityErrorMessage.text(for: error).contains("goes against the Community Guidelines"))
    }

    func testOtherCodesMapToSentences() {
        XCTAssertEqual(
            CommunityErrorMessage.text(for: CommunityFixtures.structured(429, "daily_limit_reached")),
            "You've reached today's posting limit. Try again tomorrow."
        )
        XCTAssertEqual(
            CommunityErrorMessage.text(for: CommunityFixtures.structured(409, "handle_taken")),
            "That handle is taken. Try another one."
        )
        XCTAssertTrue(CommunityErrorMessage.needsProfile(CommunityFixtures.structured(403, "community_profile_required")))
    }

    func testAIPostsShowLabelVerbatimAndOfferNoReportOrBlock() {
        let ai = CommunityFixtures.post(kind: .ai, isDailyPost: true, aiLabel: "AI-generated · Daily Post")
        XCTAssertEqual(CommunityPresentation.aiLabel(ai), "AI-generated · Daily Post")
        XCTAssertEqual(CommunityPresentation.authorName(ai), "LuminaVault")
        XCTAssertFalse(CommunityPresentation.canReport(ai))
        XCTAssertFalse(CommunityPresentation.canBlock(ai))
    }

    func testOwnPostsOfferDeleteNotReport() {
        let own = CommunityFixtures.post(isOwn: true)
        XCTAssertTrue(CommunityPresentation.canDelete(own))
        XCTAssertFalse(CommunityPresentation.canReport(own))
        XCTAssertFalse(CommunityPresentation.canBlock(own))
        let other = CommunityFixtures.post()
        XCTAssertTrue(CommunityPresentation.canReport(other))
        XCTAssertTrue(CommunityPresentation.canBlock(other))
        XCTAssertFalse(CommunityPresentation.canDelete(other))
    }

    func testComposeAccess() {
        XCTAssertEqual(CommunityComposeAccess(me: CommunityFixtures.me()), .allowed)
        XCTAssertEqual(CommunityComposeAccess(me: CommunityFixtures.me(postingEnabled: false)), .postingDisabled)
        XCTAssertEqual(CommunityComposeAccess(me: CommunityFixtures.me(profile: nil)), .needsProfile)
        XCTAssertEqual(
            CommunityComposeAccess(me: CommunityFixtures.me(profile: CommunityFixtures.profile(termsVersion: 1), termsVersionRequired: 2)),
            .needsProfile
        )
    }

    func testHandleValidationMatchesServerPattern() {
        XCTAssertTrue(CommunityProfileSetupSheet.isValidHandle("ana_99"))
        XCTAssertFalse(CommunityProfileSetupSheet.isValidHandle("ab"))
        XCTAssertFalse(CommunityProfileSetupSheet.isValidHandle("Ana"))
        XCTAssertFalse(CommunityProfileSetupSheet.isValidHandle("a-b-c"))
    }

    func testPaletteOffersCommunityOnlyWhenEnabled() {
        XCTAssertFalse(MainTabView.paletteEntries(communityEnabled: false).contains { $0.id == "community" })
        let entries = MainTabView.paletteEntries(communityEnabled: true)
        XCTAssertTrue(entries.contains { $0.id == "community" })
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
    }
}

@MainActor
final class CommunityDailyPostTests: XCTestCase {
    func testEmptyBodyFrom204DecodesAsNoPost() throws {
        // BaseHTTPClient substitutes `{}` for an empty 2xx body.
        let decoded = try JSONDecoder.hvDefault.decode(CommunityDailyPostResponse.self, from: Data("{}".utf8))
        XCTAssertNil(decoded.post)
    }

    func testPostBodyDecodes() throws {
        let post = CommunityFixtures.post(kind: .ai, isDailyPost: true, aiLabel: "AI-generated · Daily Post")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(post)
        let decoded = try JSONDecoder.hvDefault.decode(CommunityDailyPostResponse.self, from: data)
        XCTAssertEqual(decoded.post?.id, post.id)
        XCTAssertEqual(decoded.post?.aiLabel, "AI-generated · Daily Post")
    }

    func testHomeRowHiddenWhenNoPostToday() {
        let client = StubCommunityClient()
        client.dailyResult = .success(nil)
        let sut = HomeDailyPostViewModel(client: client)
        let exp = expectation(description: "load")
        Task { await sut.load(); exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertTrue(sut.isEnabled)
        XCTAssertNil(sut.post)
        XCTAssertTrue(sut.isHidden)
    }

    func testHomeRowHiddenWhenBoardDisabled() {
        let client = StubCommunityClient()
        client.meResult = .success(CommunityFixtures.me(enabled: false))
        client.dailyResult = .success(CommunityFixtures.post(kind: .ai, isDailyPost: true))
        let sut = HomeDailyPostViewModel(client: client)
        let exp = expectation(description: "load")
        Task { await sut.load(); exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertTrue(sut.isHidden)
    }

    func testRequestsEncodeCamelCase() throws {
        let endpoint = CommunityEndpoints.UpsertProfile(request: CommunityProfileUpsertRequest(
            handle: "ana", displayName: "Ana", acceptTerms: true, termsVersion: 1
        ))
        let data = try endpoint.encoder.encode(AnyEncodable(try XCTUnwrap(endpoint.body)))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"displayName\""))
        XCTAssertTrue(json.contains("\"acceptTerms\""))
        XCTAssertFalse(json.contains("display_name"))
    }

    func testCursorIsEscapedInPath() {
        let path = CommunityEndpoints.Threads(cursor: "a+b/c=", limit: 20).path
        XCTAssertEqual(path, "/v1/community/posts?limit=20&cursor=a%2Bb%2Fc%3D")
        XCTAssertEqual(CommunityEndpoints.Threads(cursor: nil, limit: 20).path, "/v1/community/posts?limit=20")
    }
}
