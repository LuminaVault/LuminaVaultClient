// LuminaVaultClient/LuminaVaultClient/Features/Health/HealthDashboardSection.swift
import SwiftUI

/// HER-118 — embedded section on the Vault tab. Renders a 2x2 grid of
/// metric cards, an empty state when permission is missing or no
/// samples have synced, and routes to `HealthDetailScreen` on card tap.
struct HealthDashboardSection: View {
    @Bindable var viewModel: HealthDashboardViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            switch viewModel.loadState {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
            case .loaded:
                content
            case let .failed(message):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text("Couldn't load health metrics")
                        .font(.subheadline)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .task { await viewModel.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.permissionState != .granted || !viewModel.anyMetricHasSamples {
            HealthEmptyState(permissionState: viewModel.permissionState) {
                await viewModel.connectHealthKit()
            }
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(HealthMetric.allCases) { metric in
                    NavigationLink {
                        HealthDetailScreen(metric: metric, viewModel: viewModel)
                    } label: {
                        HealthDashboardCard(
                            metric: metric,
                            aggregate: viewModel.aggregates[metric.serverType],
                            latestValue: viewModel.latestValue(for: metric),
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Health")
                .font(.headline)
            Spacer()
            if case .loaded = viewModel.loadState {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }
}
