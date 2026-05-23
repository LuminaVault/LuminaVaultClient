// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Conversion/Models/ConversionFunnelStep.swift
//
// HER-287 — 12-step ladder for the conversion onboarding funnel. The
// 13th archetype screen (paywall) is NOT a step here: when the funnel
// completes, it sets `appState.pendingPaywallID` and the HER-211
// universal root sheet handles presentation.

import Foundation

enum ConversionFunnelStep: Int, CaseIterable, Sendable {
    case welcome             // 1
    case goal                // 2
    case painPoints          // 3
    case socialProof         // 4
    case swipeCards          // 5
    case personalisedSolution // 6
    case comparison          // 7
    case captureSources      // 8
    case processing          // 9
    case appDemo             // 10
    case valueDelivery       // 11
    case notificationPrime   // 12

    /// Progress in `[0, 1]` shown on the top progress bar.
    var progressFraction: Double {
        Double(rawValue + 1) / Double(Self.allCases.count)
    }

    var next: ConversionFunnelStep? {
        ConversionFunnelStep(rawValue: rawValue + 1)
    }

    var previous: ConversionFunnelStep? {
        guard rawValue > 0 else { return nil }
        return ConversionFunnelStep(rawValue: rawValue - 1)
    }
}
