// LuminaVaultClient/LuminaVaultClient/API/Dashboard/DashboardProfileEndpoints.swift
//
// GET /v1/dashboard/profile — player-profile HUD counters (skills, jobs,
// sessions, badges) plus a derived power level/XP for the authenticated
// tenant.

import Foundation
import LuminaVaultShared

enum DashboardProfileEndpoints {
    struct Get: Endpoint {
        typealias Response = DashboardProfileResponse

        var path: String { "/v1/dashboard/profile" }
        var method: HTTPMethod { .get }
    }
}
