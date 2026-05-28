// LuminaVaultClient/LuminaVaultClient/Features/Health/HealthDashboardScreen.swift
import SwiftUI

/// HER-118 — full-screen wrapper around `HealthDashboardSection`. Pushed
/// from the Home tab's Health card (or any other surface that wants the
/// dashboard standalone). Owns the view model so each navigation push
/// gets a fresh state instance and refreshes on appear.
struct HealthDashboardScreen: View {
    @State private var viewModel: HealthDashboardViewModel

    init(httpClient: BaseHTTPClient, coordinator: HealthKitCoordinator?) {
        let executor = LiveHealthDashboardEndpointsExecutor(httpClient: httpClient)
        let probe: @MainActor () async -> HealthDashboardViewModel.PermissionState = {
            guard let coordinator else { return .unknown }
            return mapPermission(await coordinator.currentPermissionState())
        }
        let request: @MainActor () async -> Void = {
            await coordinator?.requestAuthorizationIfNeeded()
        }
        _viewModel = State(initialValue: HealthDashboardViewModel(
            endpointsExecutor: executor,
            permissionProbe: probe,
            permissionRequest: request,
        ))
    }

    var body: some View {
        ScrollView {
            HealthDashboardSection(viewModel: viewModel)
                .padding(20)
        }
        .navigationTitle("Health")
        .navigationBarTitleDisplayMode(.large)
    }
}

@MainActor
private func mapPermission(
    _ coordinator: HealthKitCoordinator.PermissionState,
) -> HealthDashboardViewModel.PermissionState {
    switch coordinator {
    case .granted: .granted
    case .denied: .denied
    case .notDetermined: .notDetermined
    }
}
