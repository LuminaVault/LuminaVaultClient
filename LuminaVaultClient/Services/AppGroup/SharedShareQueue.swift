// LuminaVaultClient/LuminaVaultClient/Services/AppGroup/SharedShareQueue.swift
//
// HER-258 — queue semantics around `pendingShares.json` in the App Group
// container. Both the extension (append) and the main app (drain/remove)
// go through this type so the file format stays in one place.

import Foundation

/// Append-only queue from the extension's POV; load-and-remove from the
/// host app's POV. The file format is a flat JSON array — small (rarely
/// more than a handful of entries between launches) and trivially
/// debuggable by inspecting the file on a sysdiagnose pull.
enum SharedShareQueue {
    /// Append a single pending share. Read-modify-write: not safe under
    /// concurrent writers, but the extension and the host rarely overlap;
    /// this is sufficient for the small share-sheet queue.
    static func append(_ share: PendingShare) throws {
        var pending = SharedAppGroup.read([PendingShare].self, from: SharedAppGroup.FileName.pendingShares) ?? []
        pending.append(share)
        try SharedAppGroup.write(pending, to: SharedAppGroup.FileName.pendingShares)
    }

    static func appendImage(
        id: UUID = UUID(),
        data: Data,
        contentType: String,
        fileExtension: String,
        note: String?,
        spaceID: UUID?
    ) throws -> PendingShare {
        let assetFileName = "\(id.uuidString).\(fileExtension)"
        try writeAsset(data, named: assetFileName)
        let share = PendingShare(
            id: id,
            imageAssetFileName: assetFileName,
            contentType: contentType,
            fileExtension: fileExtension,
            note: note,
            spaceID: spaceID,
        )
        do {
            try append(share)
            return share
        } catch {
            try? deleteAsset(named: assetFileName)
            throw error
        }
    }

    /// Read all pending shares. Returns `[]` when the file is missing
    /// (first run, or just after a successful drain).
    static func loadAll() -> [PendingShare] {
        SharedAppGroup.read([PendingShare].self, from: SharedAppGroup.FileName.pendingShares) ?? []
    }

    /// Legacy drain helper retained for older call sites/tests. New code
    /// should prefer `loadAll` + `remove(id:)` so per-row failures stay
    /// queued.
    static func drainAndClear() throws -> [PendingShare] {
        let all = loadAll()
        if !all.isEmpty {
            try SharedAppGroup.delete(file: SharedAppGroup.FileName.pendingShares)
        }
        return all
    }

    /// Remove one successfully handled share without dropping unrelated
    /// queued rows. Also deletes any image sidecar for that row.
    static func remove(id: UUID) throws {
        var pending = loadAll()
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let removed = pending.remove(at: index)
        try overwrite(pending)
        if let assetFileName = removed.assetFileName {
            try? deleteAsset(named: assetFileName)
        }
    }

    /// Test seam — overwrite the queue file with an exact list. Not used
    /// in production; the extension uses `append` instead so concurrent
    /// runs don't clobber each other.
    static func overwrite(_ shares: [PendingShare]) throws {
        try SharedAppGroup.write(shares, to: SharedAppGroup.FileName.pendingShares)
    }

    static func assetData(for share: PendingShare) throws -> Data? {
        guard let assetFileName = share.assetFileName,
              let url = assetURL(named: assetFileName) else { return nil }
        return try Data(contentsOf: url)
    }

    private static func writeAsset(_ data: Data, named fileName: String) throws {
        guard let directory = SharedAppGroup.directoryURL(named: SharedAppGroup.DirectoryName.pendingShareAssets)
        else { throw SharedAppGroup.AccessError.containerUnavailable }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    private static func assetURL(named fileName: String) -> URL? {
        SharedAppGroup
            .directoryURL(named: SharedAppGroup.DirectoryName.pendingShareAssets)?
            .appendingPathComponent(fileName)
    }

    private static func deleteAsset(named fileName: String) throws {
        guard let url = assetURL(named: fileName) else { throw SharedAppGroup.AccessError.containerUnavailable }
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        try fm.removeItem(at: url)
    }
}
