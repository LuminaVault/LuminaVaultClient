// LuminaVaultClient/LuminaVaultClient/Features/Health/HealthDashboardViewModel.swift
import Foundation
import HealthKit
import Observation

/// HER-118 — Vault tab health dashboard state. Pulls 7-day daily
/// aggregates for the four fixed metrics in parallel and tracks the
/// HealthKit permission state so the empty-state CTA can fire when
/// the user has never granted authorization.
@Observable
@MainActor
final class HealthDashboardViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum PermissionState: Equatable {
        case unknown
        case granted
        case denied
        case notDetermined
    }

    let endpointsExecutor: any HealthDashboardEndpointsExecutor
    private let permissionProbe: @MainActor () async -> PermissionState
    private let permissionRequest: @MainActor () async -> Void

    var loadState: LoadState = .idle
    var permissionState: PermissionState = .unknown
    /// Keyed by `HealthMetric.serverType`; nil while loading or on failure.
    var aggregates: [String: HealthDailyResponse] = [:]

    init(
        endpointsExecutor: any HealthDashboardEndpointsExecutor,
        permissionProbe: @escaping @MainActor () async -> PermissionState,
        permissionRequest: @escaping @MainActor () async -> Void,
    ) {
        self.endpointsExecutor = endpointsExecutor
        self.permissionProbe = permissionProbe
        self.permissionRequest = permissionRequest
    }

    func refresh(days: Int = 7) async {
        loadState = .loading
        permissionState = await permissionProbe()

        do {
            async let sleep = endpointsExecutor.daily(type: HealthMetric.sleep.serverType, days: days)
            async let heartRate = endpointsExecutor.daily(type: HealthMetric.heartRate.serverType, days: days)
            async let hrv = endpointsExecutor.daily(type: HealthMetric.hrv.serverType, days: days)
            async let steps = endpointsExecutor.daily(type: HealthMetric.steps.serverType, days: days)
            let (s, h, v, st) = try await (sleep, heartRate, hrv, steps)
            aggregates = [
                s.type: s,
                h.type: h,
                v.type: v,
                st.type: st,
            ]
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func connectHealthKit() async {
        await permissionRequest()
        permissionState = await permissionProbe()
        if permissionState == .granted {
            await refresh()
        }
    }

    /// Returns the most recent non-zero day's value, or 0 if no samples.
    /// For Sleep, "latest" is "last night" — server stores duration as
    /// total minutes in a single `sleep_session` sample.
    func latestValue(for metric: HealthMetric) -> Double {
        guard let aggregate = aggregates[metric.serverType] else { return 0 }
        if let last = aggregate.days.last(where: { $0.sampleCount > 0 }) {
            return last.value
        }
        return 0
    }

    var anyMetricHasSamples: Bool {
        aggregates.values.contains { resp in
            resp.days.contains { $0.sampleCount > 0 }
        }
    }
}

/// Indirection seam so unit + snapshot tests can supply canned responses
/// without booting `BaseHTTPClient`.
protocol HealthDashboardEndpointsExecutor: Sendable {
    func daily(type: String, days: Int) async throws -> HealthDailyResponse
    func listSamples(type: String, limit: Int) async throws -> HealthListResponse
}

struct LiveHealthDashboardEndpointsExecutor: HealthDashboardEndpointsExecutor {
    let httpClient: BaseHTTPClient

    func daily(type: String, days: Int) async throws -> HealthDailyResponse {
        try await httpClient.execute(HealthEndpoints.Daily(type: type, days: days))
    }

    func listSamples(type: String, limit: Int) async throws -> HealthListResponse {
        try await httpClient.execute(HealthEndpoints.ListSamples(type: type, limit: limit))
    }
}
