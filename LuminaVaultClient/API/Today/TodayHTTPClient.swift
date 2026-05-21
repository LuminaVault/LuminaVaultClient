// LuminaVaultClient/LuminaVaultClient/API/Today/TodayHTTPClient.swift
//
// HER-177 — BaseHTTPClient-backed Today feed.

import Foundation
import LuminaVaultShared

protocol TodayClientProtocol: Sendable {
    func outputs(since: Date?, limit: Int?) async throws -> SkillOutputListResponse
}

final class TodayHTTPClient: TodayClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func outputs(since: Date? = nil, limit: Int? = 50) async throws -> SkillOutputListResponse {
        try await client.execute(TodayEndpoints.Outputs(since: since, limit: limit))
    }
}
