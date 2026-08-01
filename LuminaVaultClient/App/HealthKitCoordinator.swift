// LuminaVaultClient/LuminaVaultClient/App/HealthKitCoordinator.swift
//
// Glue between AppState's auth lifecycle and HealthKitService. Hold one
// instance for the lifetime of the app; call `start()` after login,
// `stop()` after sign-out.
//
// `start()`:
//   1. Request authorization (idempotent).
//   2. Enable background delivery for every metric.
//   3. Kick a foreground sync so the UI shows recent data immediately.
//
// `start()` is safe to call repeatedly — HealthKit's auth state is
// remembered and the anchored queries are incremental.

import Foundation
import HealthKit
import OSLog

private let log = Logger(subsystem: "com.luminavault", category: "healthkit.coordinator")

@MainActor
final class HealthKitCoordinator {
    private let service: HealthKitService
    private(set) var lastSyncDate: Date?
    private(set) var isStarted = false

    init(service: HealthKitService) {
        self.service = service
    }

    func start() async {
        guard !isStarted else { return }
        isStarted = true
        do {
            try await service.requestAuthorization()
            await service.enableBackgroundDelivery()
            let pushed = try await service.syncAll()
            lastSyncDate = Date()
            log.info("HealthKit started; initial sync pushed \(pushed) events")
        } catch {
            log.error("HealthKit start failed: \(error.localizedDescription)")
            isStarted = false
        }
    }

    func sync() async {
        guard isStarted else { return }
        do {
            let pushed = try await service.syncAll()
            lastSyncDate = Date()
            log.info("HealthKit foreground sync pushed \(pushed) events")
        } catch {
            log.error("HealthKit sync failed: \(error.localizedDescription)")
        }
    }

    func stop() async {
        guard isStarted else { return }
        await service.disableBackgroundDelivery()
        isStarted = false
        log.info("HealthKit stopped")
    }

    /// Resume syncing on launch **without** prompting.
    ///
    /// `start()` calls `requestAuthorization()`, which shows the system consent
    /// sheet. Firing that from `AppState.init` would ambush the user with a
    /// Health prompt the instant they sign in, with no explanation and no
    /// context — the kind of thing App Review rejects. Consent belongs to the
    /// explicit "Connect HealthKit" CTA on the Health dashboard.
    ///
    /// So on launch we only resume when access was already granted in a
    /// previous session.
    func resumeIfAuthorized() async {
        guard !isStarted else { return }
        guard await currentPermissionState() == .granted else {
            log.info("HealthKit not authorized yet — waiting for the explicit Connect action")
            return
        }
        await start()
    }

    /// HER-118 — permission summary for the dashboard empty state.
    ///
    /// Delegates to `HealthKitService.readAuthorizationState()`. The previous
    /// implementation called `store.authorizationStatus(for:)`, which reports
    /// **write** status; since this app requests `toShare: []` that always
    /// returned `.sharingDenied`, so the dashboard showed "denied" even to
    /// users who had granted full read access.
    func currentPermissionState() async -> PermissionState {
        switch await service.readAuthorizationState() {
        case .granted: return .granted
        case .denied, .unavailable: return .denied
        case .notDetermined: return .notDetermined
        // An inconclusive probe must not be rendered as a denial — offering
        // "Connect" is recoverable, claiming denial is a dead end.
        case .unknown: return .notDetermined
        }
    }

    /// HER-118 — explicit re-authorization trigger for the dashboard's
    /// "Connect HealthKit" CTA. Idempotent; safe to call repeatedly.
    func requestAuthorizationIfNeeded() async {
        do {
            try await service.requestAuthorization()
            await service.enableBackgroundDelivery()
        } catch {
            log.error("HealthKit reauth failed: \(error.localizedDescription)")
        }
    }

    enum PermissionState: Equatable {
        case granted
        case denied
        case notDetermined
    }
}
