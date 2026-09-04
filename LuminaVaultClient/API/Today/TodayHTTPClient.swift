// LuminaVaultClient/LuminaVaultClient/API/Today/TodayHTTPClient.swift
//
// HER-177 — BaseHTTPClient-backed Today feed.

import Foundation
import LuminaVaultShared

protocol TodayClientProtocol: Sendable {
    /// `before` pages backwards through history; pass the previous
    /// response's `nextCursor`. `nil` reads the newest page.
    func outputs(since: Date?, before: Date?, limit: Int?) async throws -> SkillOutputListResponse
}

extension TodayClientProtocol {
    func outputs(since: Date?, limit: Int?) async throws -> SkillOutputListResponse {
        try await outputs(since: since, before: nil, limit: limit)
    }
}

final class TodayHTTPClient: TodayClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func outputs(since: Date? = nil, before: Date? = nil, limit: Int? = 50) async throws -> SkillOutputListResponse {
        try await client.execute(TodayEndpoints.Outputs(since: since, before: before, limit: limit))
    }
}
