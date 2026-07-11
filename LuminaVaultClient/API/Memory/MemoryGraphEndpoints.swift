// LuminaVaultClient/LuminaVaultClient/API/Memory/MemoryGraphEndpoints.swift
//
// HER-235 — GET /v1/memory/graph endpoint.
// Server contract: derived memory graph for the authenticated tenant.
// Nodes = top-scored memories. Edges = derived on read from shared tags
// + pgvector cosine similarity. No new schema; no persisted edges in v1.

import Foundation
import LuminaVaultShared

enum MemoryGraphEndpoints {
    struct Graph: Endpoint {
        typealias Response = MemoryGraphResponse

        /// Max nodes returned. Server clamps to `[1, 2000]`; default 500.
        let limit: Int?
        /// Cosine-similarity floor in `[0, 1]`. Server default 0.78.
        let similarityThreshold: Double?
        /// Per-node degree cap after merge. Server default 8, max 50.
        let maxEdgesPerNode: Int?
        /// Whether wiki/source page nodes should be included. Server default true.
        let includeWikiPages: Bool?
        /// CSV-encoded edge kinds to compute. Server default all kinds.
        let kinds: [MemoryEdgeKindDTO]?

        var path: String {
            var components = URLComponents()
            components.path = "/v1/memory/graph"
            var items: [URLQueryItem] = []
            if let limit { items.append(.init(name: "limit", value: String(limit))) }
            if let similarityThreshold {
                items.append(.init(name: "similarityThreshold", value: String(similarityThreshold)))
            }
            if let maxEdgesPerNode {
                items.append(.init(name: "maxEdgesPerNode", value: String(maxEdgesPerNode)))
            }
            if let includeWikiPages {
                items.append(.init(name: "includeWikiPages", value: String(includeWikiPages)))
            }
            if let kinds, !kinds.isEmpty {
                items.append(.init(name: "kinds", value: kinds.map(\.rawValue).joined(separator: ",")))
            }
            if !items.isEmpty { components.queryItems = items }
            // BaseHTTPClient appends `path` to its base URL — emit the path
            // plus the query string in one piece so query params survive.
            return components.path + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
        }

        var method: HTTPMethod { .get }
    }
}
