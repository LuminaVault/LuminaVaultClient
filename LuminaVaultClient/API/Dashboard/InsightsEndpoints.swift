// LuminaVaultClient/LuminaVaultClient/API/Dashboard/InsightsEndpoints.swift
//
// HER-244 — GET /v1/insights endpoint.
// Server contract: tenant-scoped list of proactive findings. Empty-list
// stub on the server side until HER-248 ships skill-backed insight
// generation.

import Foundation
import LuminaVaultShared

enum InsightsEndpoints {
    struct List: Endpoint {
        typealias Response = InsightListResponse

        let section: InsightSection?
        let limit: Int?

        var path: String {
            var components = URLComponents()
            components.path = "/v1/insights"
            var items: [URLQueryItem] = []
            if let section {
                items.append(.init(name: "section", value: section.rawValue))
            }
            if let limit {
                items.append(.init(name: "limit", value: String(limit)))
            }
            if !items.isEmpty { components.queryItems = items }
            return components.path + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
        }

        var method: HTTPMethod { .get }
    }
}
