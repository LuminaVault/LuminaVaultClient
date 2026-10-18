// LuminaVaultClient/LuminaVaultClient/API/Resurface/ResurfaceEndpoints.swift
//
// GET /v1/me/resurface?limit=N — the "to revisit" queue: memories that are
// due again, saved on this day a while ago, or fading. The response is the
// shared `ResurfaceResponse`; the server writes camelCase, which the default
// `.convertFromSnakeCase` decoder leaves untouched.

import Foundation
import LuminaVaultShared

nonisolated enum ResurfaceEndpoints {
    nonisolated struct Get: Endpoint {
        typealias Response = ResurfaceResponse
        let limit: Int

        var path: String {
            "/v1/me/resurface?limit=\(limit)"
        }

        var method: HTTPMethod {
            .get
        }

        /// Home loads this passively; a 402 hides the card rather than
        /// sliding a paywall over whatever the user was doing.
        var presentsPaywallOn402: Bool {
            false
        }
    }
}
