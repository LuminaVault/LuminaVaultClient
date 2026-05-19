// LuminaVaultClient/LuminaVaultClient/Services/Sync/SyncQueueStore.swift
import Foundation
import SwiftData

/// HER-39 — SwiftData-backed FIFO queue for `SyncOperation` rows. Wrapped
/// in `@ModelActor` so all `ModelContext` reads/writes happen on the actor
/// and stay off the main thread.
@ModelActor
actor SyncQueueStore {
    /// Inserts a pending operation. Caller is responsible for persisting
    /// any body blob (vault upload bytes) via `LocalVaultManager` beforehand
    /// — this store owns the row metadata only.
    func enqueue(_ op: SyncOperation) throws {
        modelContext.insert(op)
        try modelContext.save()
    }

    /// Returns the next eligible row for the tenant: state == .pending and
    /// `nextEligibleAt` either nil or in the past. Older rows win ties.
    func nextEligible(for tenantID: UUID, now: Date = Date()) throws -> SyncOperation? {
        var descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate { $0.tenantID == tenantID },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 32
        let candidates = try modelContext.fetch(descriptor)
        for op in candidates where op.state == .pending {
            if let eligibleAt = op.nextEligibleAt, eligibleAt > now { continue }
            return op
        }
        return nil
    }

    func pendingCount(for tenantID: UUID) throws -> Int {
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate { $0.tenantID == tenantID }
        )
        let all = try modelContext.fetch(descriptor)
        return all.filter { $0.state == .pending || $0.state == .failed }.count
    }

    func failedCount(for tenantID: UUID) throws -> Int {
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate { $0.tenantID == tenantID }
        )
        let all = try modelContext.fetch(descriptor)
        return all.filter { $0.state == .poisoned }.count
    }

    func markInFlight(_ id: UUID, attemptAt: Date = Date()) throws {
        guard let op = try fetchOne(id) else { return }
        op.state = .inFlight
        op.lastAttemptAt = attemptAt
        op.attempts += 1
        try modelContext.save()
    }

    /// Completes an op by removing it. The companion `SyncLogEntry` is
    /// inserted via `appendLog`.
    func markCompleted(_ id: UUID) throws {
        guard let op = try fetchOne(id) else { return }
        modelContext.delete(op)
        try modelContext.save()
    }

    func markFailed(_ id: UUID, nextEligibleAt: Date) throws {
        guard let op = try fetchOne(id) else { return }
        op.state = .failed
        op.nextEligibleAt = nextEligibleAt
        try modelContext.save()
    }

    func markPoisoned(_ id: UUID) throws {
        guard let op = try fetchOne(id) else { return }
        op.state = .poisoned
        try modelContext.save()
    }

    /// Reset a `.inFlight` row back to `.pending` so a foreground retry
    /// picks it up. Used when a drain task is cancelled mid-flight.
    func unmarkInFlight(_ id: UUID, nextEligibleAt: Date? = nil) throws {
        guard let op = try fetchOne(id) else { return }
        if op.state == .inFlight {
            op.state = .pending
            op.nextEligibleAt = nextEligibleAt
            try modelContext.save()
        }
    }

    func appendLog(_ entry: SyncLogEntry, retainingLast limit: Int = 50) throws {
        modelContext.insert(entry)
        // Trim the tail so the log stays small.
        let descriptor = FetchDescriptor<SyncLogEntry>(
            predicate: #Predicate { $0.tenantID == entry.tenantID },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let rows = try modelContext.fetch(descriptor)
        if rows.count > limit {
            for stale in rows.dropFirst(limit) {
                modelContext.delete(stale)
            }
        }
        try modelContext.save()
    }

    func recentLog(for tenantID: UUID, limit: Int = 20) throws -> [SyncLogEntry] {
        var descriptor = FetchDescriptor<SyncLogEntry>(
            predicate: #Predicate { $0.tenantID == tenantID },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    private func fetchOne(_ id: UUID) throws -> SyncOperation? {
        var descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
