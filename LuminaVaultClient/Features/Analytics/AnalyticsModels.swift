// LuminaVaultClient/LuminaVaultClient/Features/Analytics/AnalyticsModels.swift
//
// HER-56 — UI-only presentation models for the Deep Analytics & Patterns
// dashboard. Wire DTOs stay in LuminaVaultShared; these are the shapes the
// dashboard view binds to (suffixed `UIModel` per the repo CLAUDE.md
// client/server boundary rule).

import Foundation

/// Time window applied uniformly to every trend series on the dashboard.
enum AnalyticsRange: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case quarter

    var id: String { rawValue }

    /// Number of trailing days requested from each time-series endpoint.
    var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        }
    }

    /// Short label for the segmented range picker.
    var title: String {
        switch self {
        case .week: "7D"
        case .month: "30D"
        case .quarter: "90D"
        }
    }
}

/// One point in a trend series — a day bucket and its value.
struct TrendPointUIModel: Identifiable, Sendable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// A single chartable signal (health metric, token usage, achievement
/// unlocks, …) resolved over the selected range.
struct TrendSeriesUIModel: Identifiable, Sendable {
    /// Stable key, e.g. `"health.steps"`, `"usage.tokens"`.
    let id: String
    let title: String
    let systemImage: String
    let unit: String
    let points: [TrendPointUIModel]
    /// Latest non-placeholder value, formatted for the card headline.
    let latest: Double

    /// True when every point is a zero/gap-filled placeholder — the card
    /// renders an empty state instead of a flat line at zero.
    var isEmpty: Bool { points.allSatisfy { $0.value == 0 } }
}
