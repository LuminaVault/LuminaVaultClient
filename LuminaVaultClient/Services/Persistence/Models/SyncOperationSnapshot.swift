// LuminaVaultClient/LuminaVaultClient/Services/Persistence/Models/SyncOperationSnapshot.swift
//
// A `Sendable` copy of one `SyncOperation` row. A SwiftData model belongs to
// the context that fetched it, so `SyncQueueStore` hands `SyncManager` this
// instead of the model; `SyncManager` records progress back by `id`.

import Foundation

nonisolated struct SyncOperationSnapshot: Sendable, Equatable {
    let id: UUID
    let tenantID: UUID
    let type: OperationType
    let pathInVault: String?
    let bodyRelativePath: String?
    let metadataJSON: Data?
    let idempotencyKey: UUID
    let attempts: Int
}
