// LuminaVaultClient/LuminaVaultClient/API/Recap/RecapEndpoints.swift
//
// GET /v1/me/recap?range=7d|30d — what the user saved, learned, asked and
// revisited over a window, with the window before it for deltas.
//
// The response is the shared `MeRecapResponse`. The server writes it with
// camelCase keys; the default `.convertFromSnakeCase` decoder leaves keys
// without underscores untouched, so `previousTotals`, `streakDays` and
// `refId` decode as written.

import Foundation
import LuminaVaultShared

nonisolated enum RecapEndpoints {
    nonisolated struct Get: Endpoint {
        typealias Response = MeRecapResponse
        let range: AnalyticsRange

        var path: String {
            "/v1/me/recap?range=\(range.rawValue)"
        }

        var method: HTTPMethod {
            .get
        }

        /// Home loads this passively; a 402 belongs in the strip's own
        /// hidden state, not a paywall over whatever the user was doing.
        var presentsPaywallOn402: Bool {
            false
        }
    }
}
