// LuminaVaultClient/LuminaVaultClient/API/Dashboard/TasksEndpoints.swift
//
// HER-244 — GET /v1/tasks endpoint.
// Server contract: tenant-scoped list of long-running operations.
// Empty-list stub on the server side until HER-246 ships persistence.

import Foundation
import LuminaVaultShared

enum TasksEndpoints {
    struct List: Endpoint {
        typealias Response = TaskListResponse

        let state: TaskState?
        let limit: Int?

        var path: String {
            var components = URLComponents()
            components.path = "/v1/tasks"
            var items: [URLQueryItem] = []
            if let state {
                items.append(.init(name: "state", value: state.rawValue))
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
