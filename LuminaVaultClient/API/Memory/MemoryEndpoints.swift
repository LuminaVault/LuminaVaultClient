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

        var path: String { "/v1/memory/upsert" }
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
