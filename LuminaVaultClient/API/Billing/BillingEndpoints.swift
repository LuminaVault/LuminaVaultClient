// LuminaVaultClient/LuminaVaultClient/API/Billing/BillingEndpoints.swift
//
// HER-185 — endpoint wrappers for the billing read surface.
//   GET /v1/auth/me/billing -> MeBillingResponse

import Foundation
import LuminaVaultShared

nonisolated enum BillingEndpoints {
    /// Authoritative tier + trial snapshot for the current user. Returned
    /// shape matches `MeBillingResponse` in `LuminaVaultShared` and the
    /// `MeBillingResponse` schema in the server's `openapi.yaml`.
    nonisolated struct GetMeBilling: Endpoint {
        typealias Response = MeBillingResponse
        var path: String { "/v1/auth/me/billing" }
        var method: HTTPMethod { .get }
    }

    /// Metrics-only usage summary for Settings → Subscription.
    nonisolated struct GetMeUsage: Endpoint {
        typealias Response = MeUsageResponse
        var path: String { "/v1/auth/me/usage" }
        var method: HTTPMethod { .get }
    }
}
