// LuminaVaultClient/LuminaVaultClient/Features/Billing/PaywallOfferingState.swift
//
// Why the paywall can't show plans — as five distinct states rather than one
// boolean.
//
// The previous shape was `checking | available | unavailable`, and all three
// failure causes collapsed into `unavailable` with a single line of copy
// ("This build can't reach the store"), no retry, and a swallowed error. That
// is accurate for exactly one of them. The observable result was a sheet
// showing a mascot, a large gap, and a Close button — reported as "the app
// slid up an empty sheet", with nothing in logs to say which cause it was.

import Foundation

enum PaywallOfferingState: Equatable {
    case checking
    case available
    /// The RC SDK never booted: `LV_RC_API_KEY` is empty or a placeholder.
    /// This is the **normal, correct** state for a TestFlight build — the Beta
    /// xcconfig ships without a store key deliberately, so nothing can be sold
    /// there. Entitlements are unaffected; they come from server truth.
    case notConfigured
    /// The offerings fetch threw — no network, a rejected key, no App Store
    /// account on the device. Transient, so this is the one state with a retry.
    case fetchFailed(String)
    /// The SDK is configured and the fetch succeeded, but there is no offering
    /// with packages to show. A dashboard gap, fixable only off-device — which
    /// is why it must not tell the user to try again.
    case empty

    /// True when RevenueCatUI's own paywall should be rendered.
    var showsStorePaywall: Bool { self == .available }

    /// Stable token for telemetry, so the three failure causes can be told
    /// apart in production. Not showing this distinction anywhere is how the
    /// blank sheet survived as long as it did.
    var telemetryReason: String? {
        switch self {
        case .checking, .available: nil
        case .notConfigured: "not_configured"
        case .fetchFailed: "fetch_failed"
        case .empty: "empty"
        }
    }
}

/// The decision, lifted out of the view so it can be tested without StoreKit,
/// a network, or a configured RevenueCat.
enum PaywallOfferingResolver {
    /// - Parameters:
    ///   - isConfigured: `Purchases.isConfigured`.
    ///   - fetchFailure: localized description if `offerings()` threw.
    ///   - availablePackageCount: packages on the resolved offering; `nil`
    ///     when no offering matched at all. Both mean "nothing to show", and
    ///     both are `.empty` — the distinction that matters to the user is
    ///     whether retrying could help, and here it cannot.
    static func state(
        isConfigured: Bool,
        fetchFailure: String?,
        availablePackageCount: Int?
    ) -> PaywallOfferingState {
        guard isConfigured else { return .notConfigured }
        if let fetchFailure { return .fetchFailed(fetchFailure) }
        guard let availablePackageCount, availablePackageCount > 0 else { return .empty }
        return .available
    }
}
