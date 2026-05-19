import Foundation
import SwiftData

/// HER-39 — one queued mutating operation against the server. The sync engine
/// (`SyncManager`, Phase D) drains pending rows in FIFO order and replays them
/// to the Hummingbird backend. The server's idempotency middleware
/// (`IdempotencyMiddleware`, Phase A) keys off `idempotencyKey` so retries
/// after a network drop never double-create.
@Model
final class SyncOperation {
    @Attribute(.unique) var id: UUID
    var tenantID: UUID
    /// Stored as raw value so SwiftData can index/query on it cheaply.
    private var typeRawValue: String
    /// Relative path inside the tenant's vault (server-side). Optional for
    /// operations that don't address a single path (`triggerCompile`).
    var pathInVault: String?
    /// Absolute URL of the buffered request body on disk when the operation
    /// carries one (`uploadFile`). Bodies live under
    /// `Documents/vault/<tenantID>/.lumina/queue/<id>.bin`.
    var bodyRelativePath: String?
    /// JSON-encoded metadata for operations whose body isn't a file blob —
    /// e.g. `moveFile { newPath }`, `triggerCompile { vaultFileIds }`.
    var metadataJSON: Data?
    /// Stable across retries. Sent to the server as the `Idempotency-Key`
    /// header so a retry after a network drop hits the dedup cache.
    var idempotencyKey: UUID
    var createdAt: Date
    var lastAttemptAt: Date?
    var attempts: Int
    /// Earliest wall-clock at which this op is eligible for replay (backoff
    /// schedule). Nil means immediately eligible.
    var nextEligibleAt: Date?
    private var stateRawValue: String

    var type: OperationType {
        get { OperationType(rawValue: typeRawValue) ?? .uploadFile }
        set { typeRawValue = newValue.rawValue }
    }

    var state: PendingState {
        get { PendingState(rawValue: stateRawValue) ?? .pending }
        set { stateRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        tenantID: UUID,
        type: OperationType,
        pathInVault: String? = nil,
        bodyRelativePath: String? = nil,
        metadataJSON: Data? = nil,
        idempotencyKey: UUID = UUID(),
        createdAt: Date = Date(),
        lastAttemptAt: Date? = nil,
        attempts: Int = 0,
        nextEligibleAt: Date? = nil,
        state: PendingState = .pending
    ) {
        self.id = id
        self.tenantID = tenantID
        self.typeRawValue = type.rawValue
        self.pathInVault = pathInVault
        self.bodyRelativePath = bodyRelativePath
        self.metadataJSON = metadataJSON
        self.idempotencyKey = idempotencyKey
        self.createdAt = createdAt
        self.lastAttemptAt = lastAttemptAt
        self.attempts = attempts
        self.nextEligibleAt = nextEligibleAt
        self.stateRawValue = state.rawValue
    }
}

enum OperationType: String, Codable, Sendable, CaseIterable {
    case uploadFile
    case deleteFile
    case moveFile
    case triggerCompile
}

enum PendingState: String, Codable, Sendable, CaseIterable {
    case pending
    case inFlight
    case failed
    /// More than the retry cap (5) — operation parked until manual
    /// intervention from the Settings screen.
    case poisoned
}
