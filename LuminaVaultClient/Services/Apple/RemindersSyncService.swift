// LuminaVaultClient/LuminaVaultClient/Services/Apple/RemindersSyncService.swift
//
// Apple Reminders (EventKit) → LuminaVault server bridge.
//
// Promotes Reminders from on-demand device-RPC (DeviceCommandExecutor's
// `fetchReminders`) to a persisted server cache Hermes reads in the
// background. `syncAll` pulls incomplete reminders + recently-completed ones
// from EventKit, maps them to `[AppleReminderInput]`, and batch-POSTs
// `/v1/reminders/sync`. Server upserts by `(tenant_id, externalID)` with
// last-writer-wins on `remoteUpdatedAt`, so re-pushing the full open set every
// sync is idempotent.
//
// EventKit has no anchor/delta cursor for reminders, so we re-scan the open
// set each run (bounded and cheap). A `lastSyncAt` timestamp is persisted in
// UserDefaults purely so the completed-window is anchored to "since last sync"
// (tombstoning items the user just checked off). Re-sync fires on
// `.EKEventStoreChanged` and app-foreground via the coordinator.
//
// Reuses the EventKit full-access auth pattern from `DeviceCommandExecutor`.

import EventKit
import Foundation
import LuminaVaultShared
import OSLog

private let log = Logger(subsystem: "com.luminavault", category: "reminders.sync")

actor RemindersSyncService {
    private let store: EKEventStore
    private let httpClient: BaseHTTPClient
    private let anchor: RemindersSyncAnchor

    /// Completed reminders are only re-synced if they were completed within
    /// this look-back window from the last sync, so a freshly-checked-off item
    /// reaches the cache (server marks it completed) without re-pushing years
    /// of history on every run.
    private static let completedLookbackFallback: TimeInterval = 14 * 86400
    private static let maxBatchSize = 1000

    init(httpClient: BaseHTTPClient, anchor: RemindersSyncAnchor = .shared, store: EKEventStore = EKEventStore()) {
        self.httpClient = httpClient
        self.anchor = anchor
        self.store = store
    }

    // MARK: - Public surface

    /// Requests EventKit full reminders access. Idempotent — the system
    /// remembers the previous answer; throws only when the user denies.
    func requestAuthorization() async throws {
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        guard granted else { throw RemindersSyncError.notAuthorized }
    }

    /// Foreground pull. Fetches the open set + recently-completed reminders,
    /// maps to inputs, and POSTs in chunks. The anchor only advances after a
    /// successful push so a network blip just retries the same window.
    @discardableResult
    func syncAll() async throws -> Int {
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        guard granted else { throw RemindersSyncError.notAuthorized }

        let now = Date()
        let incomplete = await fetchIncomplete()

        // Recently-completed window: from the last successful sync (minus a
        // small fallback for first run) up to now. Surfaces just-checked-off
        // items so the server flips them to completed.
        let completedSince = anchor.lastSyncAt ?? now.addingTimeInterval(-Self.completedLookbackFallback)
        let completed = await fetchCompleted(since: completedSince, until: now)

        var inputs = incomplete.map(Self.map)
        inputs.append(contentsOf: completed.map(Self.map))

        guard !inputs.isEmpty else {
            log.info("no reminders to sync")
            anchor.lastSyncAt = now
            return 0
        }

        var pushed = 0
        for chunk in inputs.chunked(into: 500) {
            guard chunk.count <= Self.maxBatchSize else { continue }
            let response = try await httpClient.execute(AppleRemindersEndpoints.Sync(reminders: chunk))
            pushed += response.inserted + response.updated
            log.info("synced reminders inserted=\(response.inserted) updated=\(response.updated) skipped=\(response.skipped)")
        }

        // Advance the anchor only after the server acked everything.
        anchor.lastSyncAt = now
        return pushed
    }

    // MARK: - EventKit fetch

    private func fetchIncomplete() async -> [EKReminder] {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }
    }

    private func fetchCompleted(since: Date, until: Date) async -> [EKReminder] {
        let predicate = store.predicateForCompletedReminders(withCompletionDateStarting: since, ending: until, calendars: nil)
        return await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }
    }

    // MARK: - Mapping

    private static func map(_ reminder: EKReminder) -> AppleReminderInput {
        var dueAt: Date?
        if let comps = reminder.dueDateComponents {
            dueAt = Calendar.current.date(from: comps)
        }
        let priority = reminder.priority == 0 ? nil : reminder.priority
        return AppleReminderInput(
            externalID: reminder.calendarItemIdentifier,
            title: reminder.title ?? "Reminder",
            notes: reminder.notes,
            dueAt: dueAt,
            completed: reminder.isCompleted,
            completedAt: reminder.completionDate,
            listName: reminder.calendar?.title,
            priority: priority,
            remoteUpdatedAt: reminder.lastModifiedDate
        )
    }
}

enum RemindersSyncError: LocalizedError {
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Reminders access denied."
        }
    }
}

// MARK: - Anchor persistence

/// Persists the last successful sync timestamp so the completed-reminders
/// window stays anchored across launches. UserDefaults is fine — the value is
/// not sensitive. Mirrors `AnchorStore` (HealthKit).
final class RemindersSyncAnchor: @unchecked Sendable {
    static let shared = RemindersSyncAnchor(defaults: .standard)

    private let defaults: UserDefaults
    private let key = "lv.reminders.lastSyncAt"

    init(defaults: UserDefaults) { self.defaults = defaults }

    var lastSyncAt: Date? {
        get {
            let t = defaults.double(forKey: key)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    func reset() { defaults.removeObject(forKey: key) }
}

// MARK: - Array chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}
