// LuminaVaultClient/LuminaVaultClient/API/Memory/MemoryQueryEndpoints.swift
//
// HER-157 — query endpoint wrappers. Server contract:
//   POST /v1/query  -> QueryResponse  (JWT + .memoryQuery entitlement)

import Foundation

enum MemoryQueryEndpoints {
    struct Query: Endpoint {
        typealias Response = QueryResponse
        let query: String
        let limit: Int?

        var path: String { "/v1/query" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { QueryRequestPayload(query: query, limit: limit) }
        var encoder: JSONEncoder {
            let e = JSONEncoder()
            e.keyEncodingStrategy = .convertToSnakeCase
            return e
        }
    }
}

private struct QueryRequestPayload: Encodable, Sendable {
    let query: String
    let limit: Int?
}
