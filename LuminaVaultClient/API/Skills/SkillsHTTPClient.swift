// LuminaVaultClient/LuminaVaultClient/API/Skills/SkillsHTTPClient.swift
//
// HER-247 / HER-178 — BaseHTTPClient-backed Skills API.

import Foundation
import LuminaVaultShared

protocol SkillsClientProtocol: Sendable {
    func list() async throws -> SkillListResponse
    func patch(name: String, body: SkillPatchRequest) async throws -> LuminaVaultShared.SkillDTO
    func runs(name: String, limit: Int?) async throws -> SkillRunsResponse
}

final class SkillsHTTPClient: SkillsClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func list() async throws -> SkillListResponse {
        try await client.execute(SkillsEndpoints.List())
    }

    func patch(name: String, body: SkillPatchRequest) async throws -> LuminaVaultShared.SkillDTO {
        try await client.execute(SkillsEndpoints.Patch(name: name, request: body))
    }

    func runs(name: String, limit: Int? = 50) async throws -> SkillRunsResponse {
        try await client.execute(SkillsEndpoints.Runs(name: name, limit: limit))
    }
}
