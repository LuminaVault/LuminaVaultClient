// LuminaVaultClient/LuminaVaultClient/API/Skills/SkillsEndpoints.swift
//
// HER-247 — GET /v1/skills + PATCH /v1/skills/{name} + GET /v1/skills/{name}/runs

import Foundation
import LuminaVaultShared

enum SkillsEndpoints {
    struct List: Endpoint {
        typealias Response = SkillListResponse
        var path: String { "/v1/skills" }
        var method: HTTPMethod { .get }
    }

    struct Patch: Endpoint {
        typealias Response = LuminaVaultShared.SkillDTO
        let name: String
        let request: SkillPatchRequest
        var path: String { "/v1/skills/\(name)" }
        var method: HTTPMethod { .patch }
        var body: (any Encodable)? { request }
    }

    struct Runs: Endpoint {
        typealias Response = SkillRunsResponse
        let name: String
        let limit: Int?
        var path: String {
            guard let limit else { return "/v1/skills/\(name)/runs" }
            return "/v1/skills/\(name)/runs?limit=\(limit)"
        }
        var method: HTTPMethod { .get }
    }
}
