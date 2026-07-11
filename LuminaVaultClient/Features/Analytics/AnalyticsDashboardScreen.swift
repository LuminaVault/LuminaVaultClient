// LuminaVaultClient/LuminaVaultClient/Features/Analytics/AnalyticsDashboardScreen.swift
//
// HER-56 — full-screen wrapper that owns the dashboard view model so each
// navigation push gets fresh state. Builds the four read clients from the
// shared `BaseHTTPClient`, mirroring `HealthDashboardScreen` (HER-118).

import SwiftUI

struct AnalyticsDashboardScreen: View {
    @State private var viewModel: AnalyticsDashboardViewModel
    // HER-248 — passed to the Patterns section so insight cards can push
    // the shared detail screen.
    private let httpClient: BaseHTTPClient
    private let onOpenRecommendation: (String) -> Void

    init(httpClient: BaseHTTPClient, onOpenRecommendation: @escaping (String) -> Void = { _ in }) {
        self.httpClient = httpClient
        self.onOpenRecommendation = onOpenRecommendation
        _viewModel = State(initialValue: AnalyticsDashboardViewModel(
            analytics: AnalyticsHTTPClient(client: httpClient),
            insights: InsightsHTTPClient(client: httpClient),
        ))
    }

    var body: some View {
        AnalyticsDashboardView(vm: viewModel, httpClient: httpClient,
                               onOpenRecommendation: onOpenRecommendation)
    }
}
