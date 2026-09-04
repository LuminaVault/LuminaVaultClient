// LuminaVaultClient/LuminaVaultClient/API/Today/TodayEndpoints.swift
//
// HER-177 — GET /v1/skills/outputs?since=<ISO>&limit=N

import Foundation
import LuminaVaultShared

enum TodayEndpoints {
    struct Outputs: Endpoint {
        typealias Response = SkillOutputListResponse
        let since: Date?
        /// Phase 2 — exclusive upper bound for paging backwards. The server
        /// hands back `nextCursor` (the oldest row's `createdAt`) whenever a
        /// full page was returned; passing it here fetches the page behind.
        /// `since` and `before` are independent: `since` is the newest the
        /// client already has, `before` is how far back it has read.
        let before: Date?
        let limit: Int?

        var path: String {
            var components = URLComponents()
            components.path = "/v1/skills/outputs"
            var items: [URLQueryItem] = []
            if let since {
                items.append(.init(name: "since", value: Self.iso.string(from: since)))
            }
            if let before {
                items.append(.init(name: "before", value: Self.iso.string(from: before)))
            }
            if let limit {
                items.append(.init(name: "limit", value: String(limit)))
            }
            if !items.isEmpty { components.queryItems = items }
            return components.path + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
        }

        var method: HTTPMethod { .get }

        private static let iso: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()
    }
}
