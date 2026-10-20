// LuminaVaultClient/LuminaVaultClient/API/Community/CommunityHTTPClient.swift
//
// BaseHTTPClient-backed `CommunityClientProtocol`. Built by
// `AppState.makeCommunityClient()`.

import Foundation
import LuminaVaultShared

protocol CommunityClientProtocol: Sendable {
    func me() async throws -> CommunityMeDTO
    func upsertProfile(_ request: CommunityProfileUpsertRequest) async throws -> CommunityProfileDTO
    func threads(cursor: String?, limit: Int) async throws -> CommunityPostPageDTO
    func createThread(_ request: CommunityPostCreateRequest) async throws -> CommunityPostDTO
    func post(id: UUID) async throws -> CommunityPostDTO
    func replies(postID: UUID, cursor: String?, limit: Int) async throws -> CommunityPostPageDTO
    func createReply(postID: UUID, _ request: CommunityReplyCreateRequest) async throws -> CommunityPostDTO
    func deletePost(id: UUID) async throws
    func report(postID: UUID, _ request: CommunityReportRequest) async throws
    /// Nil when the server has not published today's Daily Post yet (204).
    func dailyToday() async throws -> CommunityPostDTO?
    func blocks() async throws -> CommunityBlockListDTO
    func block(_ request: CommunityBlockRequest) async throws
    func unblock(profileID: UUID) async throws
    func adminQueue() async throws -> CommunityAdminQueueDTO
    func adminDecide(postID: UUID, _ request: CommunityAdminDecisionRequest) async throws
}

final class CommunityHTTPClient: CommunityClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) {
        self.client = client
    }

    func me() async throws -> CommunityMeDTO {
        try await client.execute(CommunityEndpoints.Me())
    }

    func upsertProfile(_ request: CommunityProfileUpsertRequest) async throws -> CommunityProfileDTO {
        try await client.execute(CommunityEndpoints.UpsertProfile(request: request))
    }

    func threads(cursor: String?, limit: Int) async throws -> CommunityPostPageDTO {
        try await client.execute(CommunityEndpoints.Threads(cursor: cursor, limit: limit))
    }

    func createThread(_ request: CommunityPostCreateRequest) async throws -> CommunityPostDTO {
        try await client.execute(CommunityEndpoints.CreateThread(request: request))
    }

    func post(id: UUID) async throws -> CommunityPostDTO {
        try await client.execute(CommunityEndpoints.Post(id: id))
    }

    func replies(postID: UUID, cursor: String?, limit: Int) async throws -> CommunityPostPageDTO {
        try await client.execute(CommunityEndpoints.Replies(postID: postID, cursor: cursor, limit: limit))
    }

    func createReply(postID: UUID, _ request: CommunityReplyCreateRequest) async throws -> CommunityPostDTO {
        try await client.execute(CommunityEndpoints.CreateReply(postID: postID, request: request))
    }

    func deletePost(id: UUID) async throws {
        _ = try await client.execute(CommunityEndpoints.DeletePost(id: id))
    }

    func report(postID: UUID, _ request: CommunityReportRequest) async throws {
        _ = try await client.execute(CommunityEndpoints.Report(postID: postID, request: request))
    }

    func dailyToday() async throws -> CommunityPostDTO? {
        try await client.execute(CommunityEndpoints.DailyToday()).post
    }

    func blocks() async throws -> CommunityBlockListDTO {
        try await client.execute(CommunityEndpoints.Blocks())
    }

    func block(_ request: CommunityBlockRequest) async throws {
        _ = try await client.execute(CommunityEndpoints.Block(request: request))
    }

    func unblock(profileID: UUID) async throws {
        _ = try await client.execute(CommunityEndpoints.Unblock(profileID: profileID))
    }

    func adminQueue() async throws -> CommunityAdminQueueDTO {
        try await client.execute(CommunityEndpoints.AdminQueue())
    }

    func adminDecide(postID: UUID, _ request: CommunityAdminDecisionRequest) async throws {
        _ = try await client.execute(CommunityEndpoints.AdminDecision(postID: postID, request: request))
    }
}
