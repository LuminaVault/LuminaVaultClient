// LuminaVaultClient/LuminaVaultClient/Services/CalendarSyncService.swift
//
// Apple Calendar (EventKit) → LuminaVault server bridge.
//
// Promotes Calendar from on-demand device-RPC into a persisted server cache.
// `syncNow` reads events in the window now-7d…now+90d via `EKEventStore`,
// maps them to `[AppleCalendarEventInput]` (externalID = `eventIdentifier`,
// remoteUpdatedAt = `lastModifiedDate`), and batch-POSTs `/v1/calendar/sync`.
// The server upserts by `(tenant_id, source, external_id)` with last-writer-
// wins, so re-pushing the same window is idempotent — no client-side anchor
// diffing needed (EventKit has no stable change-token across stores).
//
// A "last synced" timestamp is persisted in UserDefaults so the Data Access
// screen can show freshness and the coordinator can throttle. The service
// observes `.EKEventStoreChanged` so on-device edits trigger a resync.
//
// Mirrors `HealthKitService` (actor, async/await, structured POST batching).

import EventKit
import Foundation
import LuminaVaultShared
import OSLog

private let log = Logger(subsystem: "com.luminavault", category: "calendar.sync")

actor CalendarSyncService {
    private let store: EKEventStore
    private let httpClient: BaseHTTPClient
    private let anchorKey = "lv.calendar.lastSyncedAt"
    private let defaults: UserDefaults

    /// Sync window: a week of history (for "what happened?") through a
    /// quarter ahead (for "what's coming up?"). Matches the `calendar_query`
    /// tool's 1–90 day forward window plus a short backfill.
    private let historyDays = 7
    private let futureDays = 90

    /// Server caps the batch at 1000 events; chunk below that.
    private let chunkSize = 500

    init(httpClient: BaseHTTPClient, defaults: UserDefaults = .standard) {
        self.store = EKEventStore()
        self.httpClient = httpClient
        self.defaults = defaults
    }

    // MARK: - Authorization

    /// Request EventKit read access. Reuses the same `requestFullAccessToEvents`
    /// path `DeviceCommandExecutor` already uses for on-demand reads, so the
    /// user is never prompted twice for the same grant. Short-circuits when
    /// access was already granted so we don't re-enter the request path on
    /// every sync.
    func requestAccess() async -> Bool {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { return true }
        return (try? await store.requestFullAccessToEvents()) == true
    }

    /// Recurring events share one `eventIdentifier` across every occurrence, so
    /// the upsert key must include the occurrence start to keep each instance a
    /// distinct row. Stable + collision-free for non-recurring events too.
    private static let occurrenceFormatter = ISO8601DateFormatter()

    var lastSyncedAt: Date? {
        defaults.object(forKey: anchorKey) as? Date
    }

    // MARK: - Sync

    /// Foreground pull: fetch the window, map, batch-POST. Returns the number
    /// of events the server inserted-or-updated. A failed POST leaves the
    /// anchor untouched so the next trigger retries the same window.
    @discardableResult
    func syncNow() async throws -> Int {
        guard await requestAccess() else {
            log.info("calendar access not granted; skipping sync")
            return 0
        }

        let now = Date()
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -historyDays, to: now) ?? now
        let end = calendar.date(byAdding: .day, value: futureDays, to: now) ?? now

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let inputs: [AppleCalendarEventInput] = store.events(matching: predicate).compactMap { event in
            guard let base = event.eventIdentifier else { return nil }
            // Per-occurrence key: `eventIdentifier` alone collapses every
            // instance of a recurring series into one server row. A moved
            // single occurrence can orphan its old row (at most one phantom
            // per series; ages out of the window) — acceptable vs. a migration.
            let externalID = "\(base)|\(Self.occurrenceFormatter.string(from: event.startDate))"
            return AppleCalendarEventInput(
                externalID: externalID,
                calendarID: event.calendar?.calendarIdentifier,
                title: event.title ?? "",
                notes: event.notes,
                location: event.location,
                startsAt: event.startDate,
                endsAt: event.endDate,
                allDay: event.isAllDay,
                status: event.status == .canceled ? "cancelled" : "confirmed",
                organizer: event.organizer?.name,
                remoteUpdatedAt: event.lastModifiedDate
            )
        }

        guard !inputs.isEmpty else {
            log.info("no calendar events in window")
            defaults.set(now, forKey: anchorKey)
            return 0
        }

        var touched = 0
        for chunk in inputs.chunked(into: chunkSize) {
            let response = try await httpClient.execute(CalendarSyncEndpoints.Sync(events: chunk))
            touched += response.inserted + response.updated
            log.info("calendar sync inserted=\(response.inserted) updated=\(response.updated) skipped=\(response.skipped)")
        }
        defaults.set(now, forKey: anchorKey)
        return touched
    }

    /// Trailing-debounce timer for store-change resyncs. `.EKEventStoreChanged`
    /// fires in bursts (and for reminders edits too), so coalesce into one sync.
    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: Duration = .seconds(2)

    /// Subscribe to on-device calendar edits. Each change (trailing-)debounces
    /// into a single `syncNow`. The returned `Task` owns the observation;
    /// cancel it (or let it die with the service) to stop.
    func observeChanges() -> Task<Void, Never> {
        Task { [weak self] in
            let stream = NotificationCenter.default.notifications(named: .EKEventStoreChanged)
            for await _ in stream {
                guard let self else { return }
                await self.scheduleDebouncedSync()
            }
            await self?.cancelDebounce()
        }
    }

    private func scheduleDebouncedSync() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: self?.debounceInterval ?? .seconds(2))
            guard !Task.isCancelled, let self else { return }
            do { _ = try await self.syncNow() }
            catch { log.warning("calendar resync after change failed: \(error.localizedDescription)") }
        }
    }

    private func cancelDebounce() {
        debounceTask?.cancel()
        debounceTask = nil
    }
}

// MARK: - Array chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}
