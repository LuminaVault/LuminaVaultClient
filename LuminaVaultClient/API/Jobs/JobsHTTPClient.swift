// LuminaVaultClient/LuminaVaultClient/API/Jobs/JobsHTTPClient.swift
//
// Lumina Jobs P3 — chat→job detection + creation.
//   POST /v1/jobs/detect  → JobProposalDTO
//   POST /v1/jobs         → SkillDTO (the created scheduled job)

import Foundation
import LuminaVaultShared

protocol JobsClientProtocol: Sendable {
    func detect(text: String) async throws -> JobProposalDTO
    func create(_ request: JobCreateRequest) async throws -> LuminaVaultShared.SkillDTO
}

enum JobsEndpoints {
    struct Detect: Endpoint {
        typealias Response = JobProposalDTO
        let text: String
        var path: String { "/v1/jobs/detect" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { ["text": text] }
    }

    struct Create: Endpoint {
        typealias Response = LuminaVaultShared.SkillDTO
        let request: JobCreateRequest
        var path: String { "/v1/jobs" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }
}

final class JobsHTTPClient: JobsClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func detect(text: String) async throws -> JobProposalDTO {
        try await client.execute(JobsEndpoints.Detect(text: text))
    }

    func create(_ request: JobCreateRequest) async throws -> LuminaVaultShared.SkillDTO {
        try await client.execute(JobsEndpoints.Create(request: request))
    }
}
