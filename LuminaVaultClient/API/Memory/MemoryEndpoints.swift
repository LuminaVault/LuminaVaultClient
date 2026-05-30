// LuminaVaultClient/LuminaVaultClient/API/Memory/MemoryEndpoints.swift
//
// HER-34 — endpoint wrappers for the memory write surface.
//   POST /v1/memory/upsert -> MemoryUpsertResponse

import Foundation
import LuminaVaultShared

enum MemoryEndpoints {
    struct Get: Endpoint {
        typealias Response = MemoryDTO
        let id: UUID

        var path: String { "/v1/memory/\(id.uuidString.lowercased())" }
        var method: HTTPMethod { .get }
    }

    struct Upsert: Endpoint {
        typealias Response = MemoryUpsertResponse
        let request: MemoryUpsertRequest
        /// HER-105 — optional Space to file the memory into. Sent as the
        /// `?space_id=` query param (mirrors `/v1/vault/files`) because the
        /// shared `MemoryUpsertRequest` DTO is a pinned package and can't gain
        /// a body field without a coordinated release.
        var spaceID: UUID? = nil

        var path: String {
            guard let spaceID else { return "/v1/memory/upsert" }
            return "/v1/memory/upsert?space_id=\(spaceID.uuidString)"
        }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
        var encoder: JSONEncoder {
            let e = JSONEncoder()
            e.keyEncodingStrategy = .convertToSnakeCase
            return e
        }
    }

    /// HER-290 — PATCH `/v1/memory/{id}` with `reviewState` body. Server
    /// validates only `pending → approved` / `pending → rejected`.
    struct Patch: Endpoint {
        typealias Response = MemoryDTO
        let id: UUID
        let request: MemoryPatchRequest

        var path: String { "/v1/memory/\(id.uuidString.lowercased())" }
        var method: HTTPMethod { .patch }
        var body: (any Encodable)? { request }
    }
}
