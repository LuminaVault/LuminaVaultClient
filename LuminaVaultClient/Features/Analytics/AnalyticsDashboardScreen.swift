// LuminaVaultClient/LuminaVaultClient/Features/Analytics/AnalyticsDashboardScreen.swift
//
// HER-56 — full-screen wrapper that owns the dashboard view model so each
// navigation push gets fresh state. Builds the four read clients from the
// shared `BaseHTTPClient`, mirroring `HealthDashboardScreen` (HER-118).

import SwiftUI

struct AnalyticsDashboardScreen: View {
    @State private var viewModel: AnalyticsDashboardViewModel

    init(httpClient: BaseHTTPClient) {
        _viewModel = State(initialValue: AnalyticsDashboardViewModel(
            health: LiveHealthDashboardEndpointsExecutor(httpClient: httpClient),
            analytics: AnalyticsHTTPClient(client: httpClient),
            achievements: AchievementsHTTPClient(client: httpClient),
            billing: BillingHTTPClient(client: httpClient),
        ))
    }

    var body: some View {
        AnalyticsDashboardView(vm: viewModel)
    }
}
