// LuminaVaultClient/LuminaVaultClient/API/Skills/SkillsHTTPClient.swift
//
// HER-247 / HER-178 — BaseHTTPClient-backed Skills API.

import Foundation
import LuminaVaultShared

protocol SkillsClientProtocol: Sendable {
    func list() async throws -> SkillListResponse
    func patch(name: String, body: SkillPatchRequest) async throws -> LuminaVaultShared.SkillDTO
    func runs(name: String, limit: Int?) async throws -> SkillRunsResponse
    /// HER-194 — manual run dispatch used by the Reflect tab.
    func run(name: String, request: SkillRunRequest) async throws -> SkillRunResponse
    /// A chat slash command (`/kb-compile`, `/patterns sleep`, `/<skill> …`),
    /// sent as typed; the server parses it.
    func runSlash(command: String) async throws -> SkillRunResponse
}

extension SkillsClientProtocol {
    /// Default for stubs that never see a slash command; the HTTP client
    /// overrides it.
    func runSlash(command _: String) async throws -> SkillRunResponse {
        throw APIError.unauthorized
    }
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

    func run(name: String, request: SkillRunRequest) async throws -> SkillRunResponse {
        try await client.execute(SkillsEndpoints.Run(name: name, request: request))
    }

    func runSlash(command: String) async throws -> SkillRunResponse {
        try await client.execute(SkillsEndpoints.Slash(request: SkillSlashCommandRequest(command: command)))
    }
}
