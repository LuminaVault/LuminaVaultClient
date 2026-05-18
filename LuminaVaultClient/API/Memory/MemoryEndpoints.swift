// LuminaVaultClient/LuminaVaultClient/API/Memory/MemoryEndpoints.swift
//
// HER-34 — endpoint wrappers for the memory write surface.
//   POST /v1/memory/upsert -> MemoryUpsertResponse

import Foundation
import LuminaVaultShared

enum MemoryEndpoints {
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
}
