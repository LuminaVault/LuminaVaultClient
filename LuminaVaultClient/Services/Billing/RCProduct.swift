// LuminaVaultClient/LuminaVaultClient/Services/Billing/RCProduct.swift
//
// HER-211 — canonical iOS StoreKit / RevenueCat product identifiers.
//
// These match the SKU IDs configured in the RevenueCat dashboard (and
// in App Store Connect — see HER-271 for the dashboard rollout). The
// strings are referenced by:
//   - `BillingService.purchase(productID:)` call sites
//   - RevenueCatUI's offering renderer (RC dashboard ties the `default`
//     and `ultimate_upsell` offerings to packages built from these IDs)
//   - Tests that drive deterministic purchase flows
//
// Entitlement identifiers (`pro`, `ultimate`) live separately on
// `RCEntitlement` in `BillingService.swift`. A product is what the user
// buys; an entitlement is what the server uses to gate features. RC
// maps products → entitlements in dashboard config.

import Foundation

enum RCProduct {
    /// $9.99/mo, 7-day free trial intro (RC dashboard).
    static let proMonthly = "pro_monthly_9_99"

    /// $79.99/year — ~33% saving vs monthly (RC dashboard).
    static let proYearly = "pro_yearly_79_99"

    /// $19.99/mo, 7-day free trial intro (RC dashboard).
    static let ultimateMonthly = "ultimate_monthly_19_99"

    /// $179.99/year — ~25% saving vs monthly (RC dashboard).
    static let ultimateYearly = "ultimate_yearly_179_99"

    /// Convenience list for regression guards in tests and any
    /// developer-mode debug pickers. Order is presentation order:
    /// monthly + yearly per tier, lowest tier first.
    static let all: [String] = [
        proMonthly,
        proYearly,
        ultimateMonthly,
        ultimateYearly,
    ]
}
