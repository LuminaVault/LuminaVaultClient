// LuminaVaultClient/LuminaVaultClient/Services/Sync/VaultRepository.swift
import Foundation
import LuminaVaultShared
import SwiftData

/// HER-39 — offline-first façade for vault + KB operations. Feature code
/// always talks to the repository; it picks the right strategy based on
/// reachability:
///
/// * **Online writes**: call the server directly with a fresh
///   `Idempotency-Key`. On success the response is returned to the caller.
///   On retryable failure the operation is enqueued so a future drain
///   can finish it.
/// * **Offline writes**: persist intent locally + enqueue the operation;
///   return `.queued` so the UI can render a "saved locally" affordance
///   instead of an error.
/// * **Reads (Phase E)**: list always reads SwiftData first and triggers
///   an asynchronous server reconcile; read-by-path serves cached disk
///   bytes when present, fetches+caches otherwise.
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
    private let modelContainer: ModelContainer
    private let localVault: LocalVaultManager
    private let indexSync: VaultIndexSync

    init(
        syncManager: SyncManager,
        kbCompileClient: KBCompileHTTPClient,
        vaultClient: VaultHTTPClient,
        networkMonitor: NetworkMonitor,
        modelContainer: ModelContainer,
        localVault: LocalVaultManager,
        tenantIDProvider: @escaping @MainActor () -> UUID?
    ) {
        self.syncManager = syncManager
        self.kbCompileClient = kbCompileClient
        self.vaultClient = vaultClient
        self.networkMonitor = networkMonitor
        self.modelContainer = modelContainer
        self.localVault = localVault
        self.indexSync = VaultIndexSync(vaultClient: vaultClient)
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

    // MARK: - Reads (Phase E)

    /// Lists the tenant's vault files. Reads SwiftData first so the UI
    /// renders instantly even offline; an async server reconcile fires in
    /// the background when reachability allows. The returned snapshot is
    /// the *current* local view — subscribers should re-fetch after the
    /// `reconcile()` task resolves to pick up any newly-cached rows.
    func listFiles() throws -> [LocalVaultFile] {
        guard let tenantID = tenantIDProvider() else {
            throw APIError.unauthorized
        }
        let descriptor = FetchDescriptor<LocalVaultFile>(
            predicate: #Predicate { $0.tenantID == tenantID },
            sortBy: [SortDescriptor(\LocalVaultFile.path)]
        )
        let context = modelContainer.mainContext
        return try context.fetch(descriptor)
    }

    /// Refreshes the local inventory from `/v1/vault/files`. Safe to call
    /// repeatedly — upserts rows by id. Pruning of rows the server no
    /// longer owns happens here too: anything not in the response and not
    /// queued for a pending write is removed.
    func reconcileIndex() async throws {
        guard let tenantID = tenantIDProvider() else {
            throw APIError.unauthorized
        }
        guard networkMonitor.isConnected else { return }

        let serverFiles = try await indexSync.fetchAllFiles()
        let serverIDs = Set(serverFiles.map(\.id))

        let context = modelContainer.mainContext
        var existing: [UUID: LocalVaultFile] = [:]
        let existingRows = try context.fetch(FetchDescriptor<LocalVaultFile>(
            predicate: #Predicate { $0.tenantID == tenantID }
        ))
        for row in existingRows { existing[row.id] = row }

        for dto in serverFiles {
            if let row = existing[dto.id] {
                row.path = dto.path
                row.contentType = dto.contentType
                row.sizeBytes = dto.sizeBytes
                row.sha256 = dto.sha256
                row.spaceID = dto.spaceId
                row.createdAt = dto.createdAt
                row.updatedAt = dto.updatedAt
            } else {
                let row = LocalVaultFile(
                    id: dto.id,
                    tenantID: tenantID,
                    path: dto.path,
                    contentType: dto.contentType,
                    sizeBytes: dto.sizeBytes,
                    sha256: dto.sha256,
                    spaceID: dto.spaceId,
                    createdAt: dto.createdAt,
                    updatedAt: dto.updatedAt
                )
                context.insert(row)
            }
        }
        // Drop locals the server no longer owns.
        for (id, row) in existing where !serverIDs.contains(id) {
            context.delete(row)
        }
        try context.save()
    }

    /// Reads a vault file by path. Disk-first: returns cached bytes when
    /// `LocalVaultFile.localBytesRelativePath` is populated; otherwise
    /// fetches from `GET /v1/vault/files/{path}`, persists the bytes to
    /// the local vault, and updates the cache pointer.
    func readFile(relativePath: String) async throws -> (Data, String) {
        guard let tenantID = tenantIDProvider() else {
            throw APIError.unauthorized
        }

        // Try cache hit first.
        if let cached = try cachedRow(for: relativePath, tenantID: tenantID),
           let bodyPath = cached.localBytesRelativePath
        {
            do {
                let data = try await localVault.readFile(relativePath: bodyPath, tenantID: tenantID)
                return (data, cached.contentType)
            } catch {
                // Pointer is stale (file deleted out-of-band) — fall through
                // and re-fetch.
            }
        }

        // Network fetch + persist.
        guard networkMonitor.isConnected else {
            throw APIError.networkFailure(URLError(.notConnectedToInternet))
        }
        let (data, contentType) = try await vaultClient.readFile(relativePath: relativePath)
        try await localVault.writeFile(data, relativePath: relativePath, tenantID: tenantID)

        if let row = try cachedRow(for: relativePath, tenantID: tenantID) {
            row.localBytesRelativePath = "raw/\(relativePath)"
            row.cachedAt = Date()
            try modelContainer.mainContext.save()
        }
        return (data, contentType)
    }

    // MARK: - Helpers

    private func cachedRow(for path: String, tenantID: UUID) throws -> LocalVaultFile? {
        var descriptor = FetchDescriptor<LocalVaultFile>(
            predicate: #Predicate { $0.tenantID == tenantID && $0.path == path }
        )
        descriptor.fetchLimit = 1
        return try modelContainer.mainContext.fetch(descriptor).first
    }

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
