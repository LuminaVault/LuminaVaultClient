import Foundation
import SwiftData

/// HER-39 — rolling log of sync attempts surfaced in
/// `Settings → Sync & Backup`. Kept small (~20 most recent rows per tenant)
/// so the UI loads instantly even after weeks of heavy use.
@Model
final class SyncLogEntry {
    @Attribute(.unique) var id: UUID
    var tenantID: UUID
    var operationID: UUID
    /// `success`, `failure`, `skipped-offline`, `poisoned`. Kept as free-form
    /// string so we can surface server-supplied error labels verbatim.
    var result: String
    var message: String?
    var timestamp: Date

    init(
        id: UUID = UUID(),
        tenantID: UUID,
        operationID: UUID,
        result: String,
        message: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.tenantID = tenantID
        self.operationID = operationID
        self.result = result
        self.message = message
        self.timestamp = timestamp
    }
}
