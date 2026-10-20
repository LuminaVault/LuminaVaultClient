// LuminaVaultClient/LuminaVaultClient/API/Community/CommunityEndpoints.swift
//
// `/v1/community` — the global board every signed-in user shares, plus the
// AI-written Daily Post. All routes are JWT; the vault header is ignored.
//
//   GET    me                         -> CommunityMeDTO
//   PUT    profile                    -> CommunityProfileDTO
//   GET    posts?cursor=&limit=       -> CommunityPostPageDTO (threads, most active first)
//   POST   posts                      -> 201 CommunityPostDTO
//   GET    posts/{id}                 -> CommunityPostDTO
//   GET    posts/{id}/replies?cursor= -> CommunityPostPageDTO (oldest first)
//   POST   posts/{id}/replies         -> 201 CommunityPostDTO
//   DELETE posts/{id}                 -> 204
//   POST   posts/{id}/report          -> 202
//   GET    daily/today                -> CommunityPostDTO, or 204 when none yet
//   GET    blocks                     -> CommunityBlockListDTO
//   POST   blocks                     -> 204
//   DELETE blocks/{profileId}         -> 204
//   GET    admin/queue                -> CommunityAdminQueueDTO (moderators)
//   POST   admin/posts/{id}/decision  -> 204 (moderators)
//
// Requests use the default `JSONEncoder` — camelCase keys, which is what the
// server decodes. Never `.convertToSnakeCase` here.

import Foundation
import LuminaVaultShared

nonisolated enum CommunityEndpoints {
    static let base = "/v1/community"

    /// Strict query-value escaping: cursors are base64url today, but
    /// `.urlQueryAllowed` alone would let a `+`, `&` or `=` through unescaped.
    static func queryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func pagePath(_ path: String, cursor: String?, limit: Int) -> String {
        var query = "limit=\(limit)"
        if let cursor, !cursor.isEmpty {
            query += "&cursor=\(queryValue(cursor))"
        }
        return "\(path)?\(query)"
    }

    static func id(_ uuid: UUID) -> String {
        uuid.uuidString.lowercased()
    }

    nonisolated struct Me: Endpoint {
        typealias Response = CommunityMeDTO
        var path: String { "\(CommunityEndpoints.base)/me" }
        var method: HTTPMethod { .get }
        /// Home asks this passively; a 402 must never slide a paywall over it.
        var presentsPaywallOn402: Bool { false }
    }

    nonisolated struct UpsertProfile: Endpoint {
        typealias Response = CommunityProfileDTO
        let request: CommunityProfileUpsertRequest
        var path: String { "\(CommunityEndpoints.base)/profile" }
        var method: HTTPMethod { .put }
        var body: (any Encodable)? { request }
    }

    nonisolated struct Threads: Endpoint {
        typealias Response = CommunityPostPageDTO
        let cursor: String?
        let limit: Int
        var path: String { CommunityEndpoints.pagePath("\(CommunityEndpoints.base)/posts", cursor: cursor, limit: limit) }
        var method: HTTPMethod { .get }
        var presentsPaywallOn402: Bool { false }
    }

    nonisolated struct CreateThread: Endpoint {
        typealias Response = CommunityPostDTO
        let request: CommunityPostCreateRequest
        var path: String { "\(CommunityEndpoints.base)/posts" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    nonisolated struct Post: Endpoint {
        typealias Response = CommunityPostDTO
        let id: UUID
        var path: String { "\(CommunityEndpoints.base)/posts/\(CommunityEndpoints.id(id))" }
        var method: HTTPMethod { .get }
        var presentsPaywallOn402: Bool { false }
    }

    nonisolated struct Replies: Endpoint {
        typealias Response = CommunityPostPageDTO
        let postID: UUID
        let cursor: String?
        let limit: Int
        var path: String {
            CommunityEndpoints.pagePath(
                "\(CommunityEndpoints.base)/posts/\(CommunityEndpoints.id(postID))/replies",
                cursor: cursor,
                limit: limit
            )
        }
        var method: HTTPMethod { .get }
        var presentsPaywallOn402: Bool { false }
    }

    nonisolated struct CreateReply: Endpoint {
        typealias Response = CommunityPostDTO
        let postID: UUID
        let request: CommunityReplyCreateRequest
        var path: String { "\(CommunityEndpoints.base)/posts/\(CommunityEndpoints.id(postID))/replies" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    nonisolated struct DeletePost: Endpoint {
        typealias Response = EmptyResponse
        let id: UUID
        var path: String { "\(CommunityEndpoints.base)/posts/\(CommunityEndpoints.id(id))" }
        var method: HTTPMethod { .delete }
    }

    nonisolated struct Report: Endpoint {
        typealias Response = EmptyResponse
        let postID: UUID
        let request: CommunityReportRequest
        var path: String { "\(CommunityEndpoints.base)/posts/\(CommunityEndpoints.id(postID))/report" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    nonisolated struct DailyToday: Endpoint {
        typealias Response = CommunityDailyPostResponse
        var path: String { "\(CommunityEndpoints.base)/daily/today" }
        var method: HTTPMethod { .get }
        var presentsPaywallOn402: Bool { false }
    }

    nonisolated struct Blocks: Endpoint {
        typealias Response = CommunityBlockListDTO
        var path: String { "\(CommunityEndpoints.base)/blocks" }
        var method: HTTPMethod { .get }
        var presentsPaywallOn402: Bool { false }
    }

    nonisolated struct Block: Endpoint {
        typealias Response = EmptyResponse
        let request: CommunityBlockRequest
        var path: String { "\(CommunityEndpoints.base)/blocks" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    nonisolated struct Unblock: Endpoint {
        typealias Response = EmptyResponse
        let profileID: UUID
        var path: String { "\(CommunityEndpoints.base)/blocks/\(CommunityEndpoints.id(profileID))" }
        var method: HTTPMethod { .delete }
    }

    nonisolated struct AdminQueue: Endpoint {
        typealias Response = CommunityAdminQueueDTO
        var path: String { "\(CommunityEndpoints.base)/admin/queue" }
        var method: HTTPMethod { .get }
        var presentsPaywallOn402: Bool { false }
    }

    nonisolated struct AdminDecision: Endpoint {
        typealias Response = EmptyResponse
        let postID: UUID
        let request: CommunityAdminDecisionRequest
        var path: String { "\(CommunityEndpoints.base)/admin/posts/\(CommunityEndpoints.id(postID))/decision" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }
}

/// Decoding shim for `GET daily/today`, which answers 204 before the day's
/// post exists. `BaseHTTPClient` turns an empty 2xx body into `{}`, so an
/// object with no keys is "none yet" and anything else is the post. Not a
/// wire DTO — the post itself is the shared `CommunityPostDTO`.
nonisolated struct CommunityDailyPostResponse: Decodable, Sendable {
    let post: CommunityPostDTO?

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue _: Int) { nil }
    }

    init(from decoder: any Decoder) throws {
        let keys = try decoder.container(keyedBy: AnyKey.self).allKeys
        post = keys.isEmpty ? nil : try CommunityPostDTO(from: decoder)
    }
}
