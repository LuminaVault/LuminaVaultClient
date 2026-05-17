// LuminaVaultClient/LuminaVaultClient/API/Memory/MemoryQueryEndpoints.swift
//
// HER-157 — query endpoint wrappers. Server contract:
//   POST /v1/query  -> QueryResponse  (JWT + .memoryQuery entitlement)
//
// HER-37 — request payload switched to LuminaVaultShared.QueryRequest now
// that the shared package owns it (v0.15.0).

import Foundation
import LuminaVaultShared

enum MemoryQueryEndpoints {
    struct Query: Endpoint {
        typealias Response = QueryResponse
        let query: String
        let limit: Int?

        var path: String { "/v1/query" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { QueryRequest(query: query, limit: limit) }
        var encoder: JSONEncoder {
            let e = JSONEncoder()
            e.keyEncodingStrategy = .convertToSnakeCase
            return e
        }
    }
}
