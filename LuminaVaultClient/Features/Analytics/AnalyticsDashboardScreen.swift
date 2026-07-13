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
    @State private var recommendationDestination: AnalyticsRecommendationDestination?

    init(httpClient: BaseHTTPClient) {
        self.httpClient = httpClient
        _viewModel = State(initialValue: AnalyticsDashboardViewModel(
            analytics: AnalyticsHTTPClient(client: httpClient),
            insights: InsightsHTTPClient(client: httpClient),
        ))
    }

    var body: some View {
        AnalyticsDashboardView(vm: viewModel, httpClient: httpClient,
                               onOpenRecommendation: openRecommendation)
            .navigationDestination(item: $recommendationDestination) { destination in
                switch destination {
                case let .memory(filter):
                    MemoryBrowserView(
                        client: MemoryHTTPClient(client: httpClient),
                        routerClient: RouterHTTPClient(client: httpClient),
                        conversationsClient: ConversationsHTTPClient(client: httpClient),
                        healthFilter: filter
                    )
                case .models:
                    ModelEffectivenessDetailView(
                        models: viewModel.modelEffectiveness,
                        ratedModelIDs: viewModel.ratedModelIDs,
                        onRate: { model, rating in
                            Task { await viewModel.rate(model, rating: rating) }
                        }
                    )
                }
            }
    }

    private func openRecommendation(_ deepLink: String) {
        recommendationDestination = AnalyticsRecommendationDestination(deepLink: deepLink)
    }
}
