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

    /// HER-194 — POST /v1/skills/{name}/run. Carries the user-supplied
    /// topic in `input`; `save: false` keeps the server from persisting
    /// to the vault so the Reflect UI can preview the rendered output
    /// and let the user decide whether to Save (cached upload — no
    /// second LLM call).
    struct Run: Endpoint {
        typealias Response = LuminaVaultShared.SkillRunResponse
        let name: String
        let request: SkillRunRequest
        var path: String { "/v1/skills/\(name)/run" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }
}
