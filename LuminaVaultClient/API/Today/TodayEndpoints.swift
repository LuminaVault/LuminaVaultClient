// LuminaVaultClient/LuminaVaultClient/API/Today/TodayEndpoints.swift
//
// HER-177 — GET /v1/skills/outputs?since=<ISO>&limit=N

import Foundation
import LuminaVaultShared

enum TodayEndpoints {
    struct Outputs: Endpoint {
        typealias Response = SkillOutputListResponse
        let since: Date?
        let limit: Int?

        var path: String {
            var components = URLComponents()
            components.path = "/v1/skills/outputs"
            var items: [URLQueryItem] = []
            if let since {
                items.append(.init(name: "since", value: Self.iso.string(from: since)))
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
