// LuminaVaultClient/LuminaVaultClient/App/CalendarSyncCoordinator.swift
//
// Glue between AppState's auth lifecycle and CalendarSyncService. Hold one
// instance for the lifetime of the app; call `start()` after login, `sync()`
// on app-foreground, `stop()` after sign-out.
//
// `start()` gates on the server-side `.calendar` consent (the user's Data
// Access toggle) before touching EventKit — sync is opt-in. When allowed it
// requests EventKit access, kicks an initial sync, and installs an
// `.EKEventStoreChanged` observer for resync on on-device edits. Mirrors
// `HealthKitCoordinator`.

import Foundation
import OSLog

private let log = Logger(subsystem: "com.luminavault", category: "calendar.coordinator")

@MainActor
final class CalendarSyncCoordinator {
    private let service: CalendarSyncService
    private let consentClient: AppleConsentClientProtocol
    private var observerTask: Task<Void, Never>?
    private(set) var isStarted = false

    init(service: CalendarSyncService, consentClient: AppleConsentClientProtocol) {
        self.service = service
        self.consentClient = consentClient
    }

    var lastSyncedAt: Date? {
        get async { await service.lastSyncedAt }
    }

    func start() async {
        guard !isStarted else { return }
        guard await isConsentAllowed() else {
            log.info("calendar sync not allowed by consent; not starting")
            return
        }
        isStarted = true
        observerTask = await service.observeChanges()
        do {
            let touched = try await service.syncNow()
            log.info("calendar sync started; initial push touched \(touched) events")
        } catch {
            log.error("calendar sync start failed: \(error.localizedDescription)")
        }
    }

    /// Foreground trigger. No-op until `start()` has cleared the consent gate.
    func sync() async {
        guard isStarted else {
            // Consent may have just been granted from the Data Access screen;
            // attempt a (cheap) re-start so a fresh toggle takes effect without
            // a relaunch.
            await start()
            return
        }
        do {
            let touched = try await service.syncNow()
            log.info("calendar foreground sync touched \(touched) events")
        } catch {
            log.error("calendar foreground sync failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        observerTask?.cancel()
        observerTask = nil
        isStarted = false
        log.info("calendar sync stopped")
    }

    private func isConsentAllowed() async -> Bool {
        do {
            let snapshot = try await consentClient.get()
            return snapshot.consents.first { $0.domain == .calendar }?.allowed ?? false
        } catch {
            // Fail closed — never sync the user's calendar without a positive
            // consent signal.
            log.warning("calendar consent check failed: \(error.localizedDescription)")
            return false
        }
    }
}
