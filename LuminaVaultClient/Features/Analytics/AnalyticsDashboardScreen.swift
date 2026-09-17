// LuminaVaultClient/LuminaVaultClient/Features/Analytics/AnalyticsDashboardScreen.swift
//
// HER-56 — wrapper that carries the dashboard's navigation destinations.
// The view model itself is owned by `InsightsTabView`, because the range
// menu is an item in that tab's navigation bar.

import SwiftUI

struct AnalyticsDashboardScreen: View {
    private let viewModel: AnalyticsDashboardViewModel
    // HER-248 — passed to the Patterns section so insight cards can push
    // the shared detail screen.
    private let httpClient: BaseHTTPClient
    @State private var recommendationDestination: AnalyticsRecommendationDestination?

    init(viewModel: AnalyticsDashboardViewModel, httpClient: BaseHTTPClient) {
        self.viewModel = viewModel
        self.httpClient = httpClient
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
