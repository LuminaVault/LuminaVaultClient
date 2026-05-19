// LuminaVaultClient/LuminaVaultClient/Services/Sync/VaultRepository.swift
import Foundation
import LuminaVaultShared

/// HER-39 — offline-first façade for vault + KB mutations. Feature code
/// always talks to the repository; it picks the right strategy based on
/// reachability:
///
/// * **Online**: call the server directly with a fresh `Idempotency-Key`.
///   On success the response is returned to the caller. On retryable
///   failure the operation is enqueued so a future drain can finish it.
/// * **Offline**: persist intent locally + enqueue the operation; return
///   `.queued` so the UI can render a "saved locally" affordance instead
///   of an error.
///
/// Phase D wires `compile()` (powering the Sync & Learn button) and the
/// queue-only `enqueueDelete`/`enqueueMove` helpers. Phase E extends the
/// repository with read-through caching.
@MainActor
final class VaultRepository {
    enum CompileOutcome: Sendable {
        case synced(KBCompileResponse)
        case queued(operationID: UUID)
    }

    private let syncManager: SyncManager
    private let kbCompileClient: KBCompileHTTPClient
    private let vaultClient: VaultHTTPClient
    private let networkMonitor: NetworkMonitor
    private let tenantIDProvider: @MainActor () -> UUID?

    init(
        syncManager: SyncManager,
        kbCompileClient: KBCompileHTTPClient,
        vaultClient: VaultHTTPClient,
        networkMonitor: NetworkMonitor,
        tenantIDProvider: @escaping @MainActor () -> UUID?
    ) {
        self.syncManager = syncManager
        self.kbCompileClient = kbCompileClient
        self.vaultClient = vaultClient
        self.networkMonitor = networkMonitor
        self.tenantIDProvider = tenantIDProvider
    }

    // MARK: - Compile

    /// Triggers a KB compile pass. Online: hits the server immediately and
    /// returns the response. Offline: enqueues a `triggerCompile` op and
    /// returns `.queued` so the UI can render a "queued — will sync when
    /// online" affordance.
    func compile(_ request: KBCompileRequest = KBCompileRequest()) async throws -> CompileOutcome {
        guard let tenantID = tenantIDProvider() else {
            throw APIError.unauthorized
        }

        if networkMonitor.isConnected {
            let key = UUID()
            do {
                let response = try await kbCompileClient.compile(request, idempotencyKey: key)
                return .synced(response)
            } catch APIError.networkFailure {
                // Network dropped after the reachability check — enqueue
                // so a future drain finishes the job.
                let op = try makeCompileOp(request: request, tenantID: tenantID, idempotencyKey: key)
                try await syncManager.enqueue(op)
                return .queued(operationID: op.id)
            }
        } else {
            let op = try makeCompileOp(request: request, tenantID: tenantID, idempotencyKey: UUID())
            try await syncManager.enqueue(op)
            return .queued(operationID: op.id)
        }
    }

    // MARK: - Queue-only entrypoints

    /// Queues a server-side file deletion. The local mirror is removed
    /// immediately so the UI reflects the change without waiting for the
    /// drain.
    @discardableResult
    func enqueueDelete(path: String, localVault: LocalVaultManager) async throws -> UUID {
        guard let tenantID = tenantIDProvider() else {
            throw APIError.unauthorized
        }
        try await localVault.deleteFile(relativePath: path, tenantID: tenantID)
        let op = SyncOperation(
            tenantID: tenantID,
            type: .deleteFile,
            pathInVault: path
        )
        try await syncManager.enqueue(op)
        return op.id
    }

    @discardableResult
    func enqueueMove(from oldPath: String, to newPath: String, localVault: LocalVaultManager) async throws -> UUID {
        guard let tenantID = tenantIDProvider() else {
            throw APIError.unauthorized
        }
        try await localVault.moveFile(from: oldPath, to: newPath, tenantID: tenantID)
        let metadata = try JSONEncoder().encode(MoveMetadata(newPath: newPath))
        let op = SyncOperation(
            tenantID: tenantID,
            type: .moveFile,
            pathInVault: oldPath,
            metadataJSON: metadata
        )
        try await syncManager.enqueue(op)
        return op.id
    }

    // MARK: - Helpers

    private func makeCompileOp(request: KBCompileRequest, tenantID: UUID, idempotencyKey: UUID) throws -> SyncOperation {
        let metadata = try JSONEncoder().encode(request)
        return SyncOperation(
            tenantID: tenantID,
            type: .triggerCompile,
            metadataJSON: metadata,
            idempotencyKey: idempotencyKey
        )
    }
}
