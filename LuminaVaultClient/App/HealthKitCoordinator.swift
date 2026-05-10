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
}
