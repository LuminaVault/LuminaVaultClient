import Foundation

/// HER-39 — owns the on-disk vault for the current tenant. Layout matches
/// the server's per-tenant `<vaultRoot>/<tenantID>/raw/<path>` convention so
/// a future "restore from backup" tool can drop a server-side tar straight
/// into the device path without translation.
///
/// Layout:
/// ```
/// Documents/vault/<tenantID>/
///   raw/        # user-facing files (mirrors server vault_files contents)
///   .lumina/    # internal metadata + sync-queue body blobs
///     queue/    # buffered request bodies for queued SyncOperation rows
/// ```
///
/// All filesystem I/O routes through this actor so the synchronization
/// boundary is explicit. Callers from the main actor await async methods.
actor LocalVaultManager {
    enum LocalVaultError: Error, Sendable, Equatable {
        case pathEscapesVault
        case pathEmpty
        case fileMissing
        case writeFailed
    }

    private let baseURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default, baseURL: URL? = nil) {
        self.fileManager = fileManager
        if let baseURL {
            self.baseURL = baseURL
        } else {
            let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.baseURL = docs.appendingPathComponent("vault", isDirectory: true)
        }
    }

    /// Root directory for one tenant. Files live under `raw/`, queue
    /// blobs and metadata under `.lumina/`.
    func vaultRootURL(for tenantID: UUID) -> URL {
        baseURL.appendingPathComponent(tenantID.uuidString, isDirectory: true)
    }

    /// Absolute URL for a tenant-relative raw vault path. Validates against
    /// path escape (e.g. `../../etc/passwd`) before returning.
    func rawFileURL(for tenantID: UUID, relativePath: String) throws -> URL {
        try Self.validate(relativePath: relativePath)
        return rawRootURL(for: tenantID).appendingPathComponent(relativePath)
    }

    /// Ensures the directory layout exists for a tenant. Idempotent.
    func ensureVaultExists(for tenantID: UUID) throws {
        let root = vaultRootURL(for: tenantID)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rawRootURL(for: tenantID), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: queueRootURL(for: tenantID), withIntermediateDirectories: true)
    }

    /// Atomic write — temp file + rename. Overwrites any existing file at
    /// the destination path.
    @discardableResult
    func writeFile(_ data: Data, relativePath: String, tenantID: UUID) throws -> URL {
        try ensureVaultExists(for: tenantID)
        let target = try rawFileURL(for: tenantID, relativePath: relativePath)
        try fileManager.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let tmp = target.appendingPathExtension("tmp-\(UUID().uuidString.prefix(8))")
        do {
            try data.write(to: tmp, options: .atomic)
        } catch {
            throw LocalVaultError.writeFailed
        }
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        try fileManager.moveItem(at: tmp, to: target)
        return target
    }

    func readFile(relativePath: String, tenantID: UUID) throws -> Data {
        let url = try rawFileURL(for: tenantID, relativePath: relativePath)
        guard fileManager.fileExists(atPath: url.path) else {
            throw LocalVaultError.fileMissing
        }
        return try Data(contentsOf: url)
    }

    func deleteFile(relativePath: String, tenantID: UUID) throws {
        let url = try rawFileURL(for: tenantID, relativePath: relativePath)
        guard fileManager.fileExists(atPath: url.path) else {
            // Idempotent: deleting an absent file is a success.
            return
        }
        try fileManager.removeItem(at: url)
    }

    /// Server-style move: refuses to overwrite an existing destination so
    /// the client surfaces 409-shaped conflicts even before contacting the
    /// network.
    func moveFile(from oldRelative: String, to newRelative: String, tenantID: UUID) throws {
        let src = try rawFileURL(for: tenantID, relativePath: oldRelative)
        let dst = try rawFileURL(for: tenantID, relativePath: newRelative)
        guard fileManager.fileExists(atPath: src.path) else {
            throw LocalVaultError.fileMissing
        }
        if fileManager.fileExists(atPath: dst.path) {
            throw LocalVaultError.writeFailed
        }
        try fileManager.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: src, to: dst)
    }

    /// Writes a buffered request body (vault upload bytes) under
    /// `<tenantID>/.lumina/queue/<operationID>.bin`. Returns the relative
    /// path stored on `SyncOperation.bodyRelativePath`.
    @discardableResult
    func writeQueuedBody(_ data: Data, operationID: UUID, tenantID: UUID) throws -> String {
        try ensureVaultExists(for: tenantID)
        let url = queueRootURL(for: tenantID).appendingPathComponent("\(operationID.uuidString).bin")
        try data.write(to: url, options: .atomic)
        return ".lumina/queue/\(url.lastPathComponent)"
    }

    func readQueuedBody(relativePath: String, tenantID: UUID) throws -> Data {
        let url = vaultRootURL(for: tenantID).appendingPathComponent(relativePath)
        guard fileManager.fileExists(atPath: url.path) else {
            throw LocalVaultError.fileMissing
        }
        return try Data(contentsOf: url)
    }

    func deleteQueuedBody(relativePath: String, tenantID: UUID) {
        let url = vaultRootURL(for: tenantID).appendingPathComponent(relativePath)
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Internal helpers

    private func rawRootURL(for tenantID: UUID) -> URL {
        vaultRootURL(for: tenantID).appendingPathComponent("raw", isDirectory: true)
    }

    private func queueRootURL(for tenantID: UUID) -> URL {
        vaultRootURL(for: tenantID)
            .appendingPathComponent(".lumina", isDirectory: true)
            .appendingPathComponent("queue", isDirectory: true)
    }

    /// Rejects empty paths, absolute paths, and any segment that would
    /// escape the tenant's vault root. Mirrors server-side
    /// `VaultController.sanitizePath` validation so the disk layout matches
    /// what the server will accept once the queue drains.
    private static func validate(relativePath: String) throws {
        guard !relativePath.isEmpty else { throw LocalVaultError.pathEmpty }
        guard !relativePath.hasPrefix("/") else { throw LocalVaultError.pathEscapesVault }
        let segments = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        for segment in segments {
            if segment == ".." || segment == "." || segment.isEmpty {
                throw LocalVaultError.pathEscapesVault
            }
        }
    }
}
