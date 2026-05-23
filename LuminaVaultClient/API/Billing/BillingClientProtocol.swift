// LuminaVaultClient/LuminaVaultClient/API/Billing/BillingClientProtocol.swift
//
// HER-185 — server-truth billing read surface. `BillingService` calls this
// to learn the authoritative tier + trial state and reconciles against the
// RevenueCat SDK snapshot.

import Foundation
import LuminaVaultShared

protocol BillingClientProtocol: Sendable {
    /// GET /v1/auth/me/billing — current user's tier, trial state, and
    /// enforcement flag as resolved by the server.
    func fetchMeBilling() async throws -> MeBillingResponse
}
