// LuminaVaultClient/LuminaVaultClient/App/RemindersSyncCoordinator.swift
//
// Glue between AppState's auth lifecycle and RemindersSyncService. Hold one
// instance for the app lifetime; call `start()` after login, `stop()` after
// sign-out.
//
// `start()`:
//   1. Check the user has allowed the `reminders` Apple data domain
//      (server-side consent via AppleConsentHTTPClient). Bail quietly if not —
//      no EventKit prompt, no sync.
//   2. Request EventKit reminders authorization (idempotent).
//   3. Kick a foreground sync.
//   4. Subscribe to `.EKEventStoreChanged` so edits re-sync, and expose
//      `sync()` for the app-foreground hook.
//
// Consent-gated so we never push reminders the user hasn't opted into; mirrors
// the server-side `.reminders` gate on POST /v1/reminders/sync.

import EventKit
import Foundation
import LuminaVaultShared
import OSLog

private let log = Logger(subsystem: "com.luminavault", category: "reminders.coordinator")

@MainActor
final class RemindersSyncCoordinator {
    private let service: RemindersSyncService
    private let consentClient: any AppleConsentClientProtocol
    private(set) var lastSyncDate: Date?
    private(set) var isStarted = false
    private var changeObserver: NSObjectProtocol?
    /// Trailing-debounce for `.EKEventStoreChanged` — it fires in bursts (and
    /// for calendar edits too), so coalesce into one resync.
    private var debounceTask: Task<Void, Never>?

    init(service: RemindersSyncService, consentClient: any AppleConsentClientProtocol) {
        self.service = service
        self.consentClient = consentClient
    }

    func start() async {
        guard !isStarted else { return }

        // Consent gate — only sync if the user allowed the Reminders domain.
        guard await isRemindersAllowed() else {
            log.info("reminders sync skipped — domain not allowed by user")
            return
        }

        isStarted = true
        do {
            try await service.requestAuthorization()
            let pushed = try await service.syncAll()
            lastSyncDate = Date()
            log.info("reminders sync started; initial push \(pushed)")
        } catch {
            log.error("reminders sync start failed: \(error.localizedDescription)")
            isStarted = false
            return
        }
        subscribeToStoreChanges()
    }

    /// Foreground / on-demand re-sync. No-op until `start()` has succeeded.
    func sync() async {
        guard isStarted else { return }
        do {
            let pushed = try await service.syncAll()
            lastSyncDate = Date()
            log.info("reminders foreground sync pushed \(pushed)")
        } catch {
            log.error("reminders sync failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isStarted else { return }
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
            self.changeObserver = nil
        }
        debounceTask?.cancel()
        debounceTask = nil
        isStarted = false
        log.info("reminders sync stopped")
    }

    // MARK: - Internals

    private func isRemindersAllowed() async -> Bool {
        do {
            let snapshot = try await consentClient.get()
            return snapshot.consents.first { $0.domain == .reminders }?.allowed ?? false
        } catch {
            log.warning("reminders consent check failed: \(error.localizedDescription)")
            return false
        }
    }

    /// EventKit fires `.EKEventStoreChanged` on any reminders/calendar edit.
    /// Coalesce by re-running `sync()`; the service re-scans the open set so
    /// adds, edits, and completions all converge.
    private func subscribeToStoreChanges() {
        guard changeObserver == nil else { return }
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleDebouncedSync() }
        }
    }

    /// Trailing-debounce: a burst of change notifications collapses into a
    /// single `sync()` after a short quiet period.
    private func scheduleDebouncedSync() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }
}
