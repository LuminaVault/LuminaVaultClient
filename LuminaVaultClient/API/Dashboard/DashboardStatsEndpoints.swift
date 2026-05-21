// LuminaVaultClient/LuminaVaultClient/API/Dashboard/DashboardStatsEndpoints.swift
//
// HER-244 — GET /v1/dashboard/stats endpoint.
// Server contract: aggregated counters (memories today + total + last
// compile timestamp) for the authenticated tenant.

import Foundation
import LuminaVaultShared

enum DashboardStatsEndpoints {
    struct Get: Endpoint {
        typealias Response = DashboardStatsResponse

        var path: String { "/v1/dashboard/stats" }
        var method: HTTPMethod { .get }
    }
}
