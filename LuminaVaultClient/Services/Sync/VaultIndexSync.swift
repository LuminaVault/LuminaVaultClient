// LuminaVaultClient/LuminaVaultClient/Services/Sync/VaultIndexSync.swift
import Foundation
import LuminaVaultShared
import OSLog

/// HER-39 — pulls `GET /v1/vault/files` (cursor-paginated) and emits the
/// resulting `VaultFileDTO`s so the repository can upsert them into the
/// local SwiftData inventory. Lives outside `SyncManager` because the
/// reconcile is a *read* and doesn't share queue state.
actor VaultIndexSync {
    private let vaultClient: VaultHTTPClient
    private let logger = Logger(subsystem: "com.lumina.fernando", category: "sync.index")

    init(vaultClient: VaultHTTPClient) {
        self.vaultClient = vaultClient
    }

    /// Walks the cursor-paginated list endpoint until exhausted. Returns
    /// every `VaultFileDTO` the server currently owns for the tenant.
    /// Caller is responsible for upserting these into SwiftData on the
    /// main actor.
    func fetchAllFiles(pageLimit: Int = 100) async throws -> [VaultFileDTO] {
        var collected: [VaultFileDTO] = []
        var cursor: Date? = nil
        repeat {
            let response = try await vaultClient.listFiles(
                spaceSlug: nil,
                q: nil,
                before: cursor,
                after: nil,
                limit: pageLimit,
            )
            collected.append(contentsOf: response.files)
            // `nextBefore` is the older end of the page when present.
            cursor = response.nextBefore
            if response.files.count < pageLimit { break }
        } while cursor != nil

        logger.debug("HER-39: indexed \(collected.count) vault files")
        return collected
    }
}
