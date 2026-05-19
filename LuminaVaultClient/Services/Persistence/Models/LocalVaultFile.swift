import Foundation
import SwiftData

/// HER-39 — local mirror of `VaultFileDTO` (server inventory). Each row maps
/// 1-to-1 to a server-side `vault_files` row plus an optional on-disk byte
/// cache. UI reads go through `VaultRepository`, which serves from SwiftData
/// first and falls back to the network.
///
/// Tenant isolation: `tenantID` is stored explicitly so a future multi-account
/// switcher can scope queries without recreating the container. All queries
/// MUST filter by `tenantID` — the client treats it the same way the server
/// treats its `tenant_id` columns.
@Model
final class LocalVaultFile {
    /// Server-issued UUID (matches `VaultFileDTO.id`). Unique across the
    /// store so re-fetching the same row updates in place.
    @Attribute(.unique) var id: UUID
    var tenantID: UUID
    var path: String
    var contentType: String
    var sizeBytes: Int64
    var sha256: String
    var spaceID: UUID?
    var createdAt: Date?
    var updatedAt: Date?
    /// Relative path under `Documents/vault/<tenantID>/raw/` when the byte
    /// payload has been written to disk. Nil means index-only — bytes are
    /// fetched on demand and cached.
    var localBytesRelativePath: String?
    /// Wall-clock timestamp of the most recent successful byte cache write.
    /// Used by background reconciliation to decide cache freshness.
    var cachedAt: Date?

    init(
        id: UUID,
        tenantID: UUID,
        path: String,
        contentType: String,
        sizeBytes: Int64,
        sha256: String,
        spaceID: UUID? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        localBytesRelativePath: String? = nil,
        cachedAt: Date? = nil
    ) {
        self.id = id
        self.tenantID = tenantID
        self.path = path
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.spaceID = spaceID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.localBytesRelativePath = localBytesRelativePath
        self.cachedAt = cachedAt
    }
}
