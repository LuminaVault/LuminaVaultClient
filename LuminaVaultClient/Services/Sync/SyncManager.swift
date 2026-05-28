// LuminaVaultClient/LuminaVaultClient/Services/Sync/SyncManager.swift
import Foundation
import LuminaVaultShared
import OSLog

/// HER-39 — drains the `SyncQueueStore` against the live API. Single-flight
/// like `TokenRefreshCoordinator`: a second `runUntilDrained` call awaits
/// the same in-progress task instead of stampeding the queue.
actor SyncManager {
    enum SyncStateSnapshot: Equatable, Sendable {
        case idle
        case syncing(pending: Int)
        case offline
        case error(message: String)
    }

    /// Maximum number of attempts before an op is parked in `.poisoned`.
    static let maxAttempts = 5

    private let queue: SyncQueueStore
    private let vaultClient: VaultHTTPClient
    private let kbCompileClient: KBCompileHTTPClient
    private let localVault: LocalVaultManager
    private let networkMonitor: NetworkMonitor
    private let logger = Logger(subsystem: "com.lumina.fernando", category: "sync")

    private var inFlight: Task<Void, Never>?
    private(set) var state: SyncStateSnapshot = .idle
    /// Callbacks fired whenever `state` changes — UI can observe via
    /// `addStateObserver`.
    private var stateObservers: [@Sendable (SyncStateSnapshot) -> Void] = []

    init(
        queue: SyncQueueStore,
        vaultClient: VaultHTTPClient,
        kbCompileClient: KBCompileHTTPClient,
        localVault: LocalVaultManager,
        networkMonitor: NetworkMonitor
    ) {
        self.queue = queue
        self.vaultClient = vaultClient
        self.kbCompileClient = kbCompileClient
        self.localVault = localVault
        self.networkMonitor = networkMonitor
    }

    // MARK: - Public surface

    func addStateObserver(_ observer: @escaping @Sendable (SyncStateSnapshot) -> Void) {
        stateObservers.append(observer)
        // Replay current state so a fresh observer is never out of sync.
        observer(state)
    }

    /// Enqueue a new operation. Caller has already persisted any body
    /// payload via `LocalVaultManager` and supplied the relative path on
    /// the `SyncOperation`.
    func enqueue(_ op: SyncOperation) async throws {
        try await queue.enqueue(op)
        await refreshState(for: op.tenantID)
        // Kick the drain — runs in the background; non-blocking for the
        // caller. If offline, the drain returns quickly without effect.
        Task { await self.runUntilDrained(tenantID: op.tenantID) }
    }

    /// Drain pending operations until the queue is empty or the network
    /// drops. Single-flight: concurrent callers await the same task.
    func runUntilDrained(tenantID: UUID) async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task<Void, Never> { [weak self] in
            await self?.drainLoop(tenantID: tenantID)
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    // MARK: - Internal drain loop

    private func drainLoop(tenantID: UUID) async {
        await updateState(.syncing(pending: 0))

        while !Task.isCancelled {
            let connected = await MainActor.run { networkMonitor.isConnected }
            guard connected else {
                await updateState(.offline)
                return
            }

            let op: SyncOperation?
            do {
                op = try await queue.nextEligible(for: tenantID)
            } catch {
                logger.error("HER-39: queue read failed: \(String(describing: error), privacy: .public)")
                await updateState(.error(message: "queue read failed"))
                return
            }
            guard let op else { break }

            do {
                try await queue.markInFlight(op.id)
                try await execute(op, tenantID: tenantID)
                try await queue.markCompleted(op.id)
                try await queue.appendLog(SyncLogEntry(
                    tenantID: tenantID,
                    operationID: op.id,
                    result: "success",
                    message: "\(op.type.rawValue)"
                ))
                // Cleanup any persisted body blob.
                if let bodyPath = op.bodyRelativePath {
                    await localVault.deleteQueuedBody(relativePath: bodyPath, tenantID: tenantID)
                }
            } catch let error as APIError where Self.isPoisonable(error) {
                try? await queue.markPoisoned(op.id)
                try? await queue.appendLog(SyncLogEntry(
                    tenantID: tenantID,
                    operationID: op.id,
                    result: "poisoned",
                    message: Self.message(for: error)
                ))
            } catch {
                let backoff = Self.backoffSeconds(attempts: op.attempts)
                let nextAt = Date().addingTimeInterval(backoff)
                if op.attempts >= Self.maxAttempts {
                    try? await queue.markPoisoned(op.id)
                    try? await queue.appendLog(SyncLogEntry(
                        tenantID: tenantID,
                        operationID: op.id,
                        result: "poisoned",
                        message: "exhausted retries: \(error.localizedDescription)"
                    ))
                } else {
                    try? await queue.markFailed(op.id, nextEligibleAt: nextAt)
                    try? await queue.appendLog(SyncLogEntry(
                        tenantID: tenantID,
                        operationID: op.id,
                        result: "failure",
                        message: error.localizedDescription
                    ))
                }
                if case APIError.networkFailure = error {
                    // Network dropped mid-drain — bail and wait for next tick.
                    await updateState(.offline)
                    return
                }
            }

            await refreshState(for: tenantID)
        }

        await updateState(.idle)
    }

    private func execute(_ op: SyncOperation, tenantID: UUID) async throws {
        switch op.type {
        case .uploadFile:
            // HER-39: capture flows that emit uploads land in a follow-up
            // ticket. The queue accepts these rows so the schema is
            // forward-compatible, but the executor parks them as
            // poisoned until the capture-side wiring lands.
            throw APIError.httpError(statusCode: 501, data: Data())
        case .deleteFile:
            guard let path = op.pathInVault else {
                throw APIError.httpError(statusCode: 400, data: Data())
            }
            try await vaultClient.deleteFile(relativePath: path, idempotencyKey: op.idempotencyKey)
        case .moveFile:
            guard let from = op.pathInVault, let metadata = op.metadataJSON,
                  let move = try? JSONDecoder().decode(MoveMetadata.self, from: metadata)
            else {
                throw APIError.httpError(statusCode: 400, data: Data())
            }
            _ = try await vaultClient.moveFile(from: from, to: move.newPath, idempotencyKey: op.idempotencyKey)
        case .triggerCompile:
            let request: KBCompileRequest
            if let metadata = op.metadataJSON,
               let decoded = try? JSONDecoder().decode(KBCompileRequest.self, from: metadata)
            {
                request = decoded
            } else {
                request = KBCompileRequest()
            }
            _ = try await kbCompileClient.compile(request, idempotencyKey: op.idempotencyKey)
        }
    }

    private func refreshState(for tenantID: UUID) async {
        let pending = (try? await queue.pendingCount(for: tenantID)) ?? 0
        if pending == 0 {
            await updateState(.idle)
        } else {
            await updateState(.syncing(pending: pending))
        }
    }

    private func updateState(_ next: SyncStateSnapshot) async {
        state = next
        let observers = stateObservers
        for observer in observers {
            observer(next)
        }
    }

    // MARK: - Helpers

    /// Permanent 4xx failures (other than 408/429) are poisonable — retrying
    /// won't change anything.
    private static func isPoisonable(_ error: APIError) -> Bool {
        if case let .httpError(statusCode, _) = error {
            return (400 ..< 500).contains(statusCode) && statusCode != 408 && statusCode != 429
        }
        // HER-188 — 402 is hoisted into a typed case; retrying won't change
        // anything until the user upgrades. Poison + surface via paywall.
        if case .paymentRequired = error { return true }
        return false
    }

    private static func message(for error: APIError) -> String {
        switch error {
        case let .httpError(status, _): "http \(status)"
        case let .networkFailure(err): "network: \(err.localizedDescription)"
        case .unauthorized: "unauthorized"
        case let .paymentRequired(_, tier):
            // HER-188 — sync queue should poison 402s so the user sees the
            // paywall once via EntitlementGate instead of looping retries.
            "payment required\(tier.map { " (\($0.rawValue))" } ?? "")"
        case let .rateLimited(retryAfter):
            "rate limited\(retryAfter.map { " (retry after \(Int($0))s)" } ?? "")"
        case .invalidURL: "invalid url"
        case let .encodingFailed(err): "encode: \(err.localizedDescription)"
        case let .decodingFailed(err): "decode: \(err.localizedDescription)"
        }
    }

    /// Exponential backoff capped at 10 minutes.
    private static func backoffSeconds(attempts: Int) -> TimeInterval {
        min(pow(2.0, Double(attempts)), 600)
    }
}

/// Body payload for `OperationType.moveFile`. Stored as JSON in
/// `SyncOperation.metadataJSON`.
struct MoveMetadata: Codable, Sendable {
    let newPath: String
}
