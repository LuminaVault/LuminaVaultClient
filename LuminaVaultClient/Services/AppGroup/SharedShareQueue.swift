// LuminaVaultClient/LuminaVaultClient/Services/AppGroup/SharedShareQueue.swift
//
// HER-258 — append + drain semantics around `pendingShares.json` in the
// App Group container. Both the extension (append) and the main app
// (drain) go through this type so the file format stays in one place.

import Foundation

/// Append-only queue from the extension's POV; drain-and-clear from the
/// host app's POV. The file format is a flat JSON array — small (rarely
/// more than a handful of entries between launches) and trivially
/// debuggable by inspecting the file on a sysdiagnose pull.
enum SharedShareQueue {
    /// Append a single pending share. Read-modify-write: not safe under
    /// concurrent writers, but the extension and the host never run in
    /// the same process at the same time, so this is the right primitive.
    static func append(_ share: PendingShare) throws {
        var pending = SharedAppGroup.read([PendingShare].self, from: SharedAppGroup.FileName.pendingShares) ?? []
        pending.append(share)
        try SharedAppGroup.write(pending, to: SharedAppGroup.FileName.pendingShares)
    }

    /// Read all pending shares. Returns `[]` when the file is missing
    /// (first run, or just after a successful drain).
    static func loadAll() -> [PendingShare] {
        SharedAppGroup.read([PendingShare].self, from: SharedAppGroup.FileName.pendingShares) ?? []
    }

    /// Drain semantics: load the array, hand it to the caller, then
    /// delete the file. The caller is responsible for enqueueing each
    /// entry into the live `CaptureQueue`; we delete BEFORE the caller
    /// processes so a partial enqueue doesn't double-replay on next
    /// launch. The downside (an enqueue that crashes after we delete
    /// would drop the row) is acceptable for v1 — the user can re-share.
    static func drainAndClear() throws -> [PendingShare] {
        let all = loadAll()
        if !all.isEmpty {
            try SharedAppGroup.delete(file: SharedAppGroup.FileName.pendingShares)
        }
        return all
    }

    /// Test seam — overwrite the queue file with an exact list. Not used
    /// in production; the extension uses `append` instead so concurrent
    /// runs don't clobber each other.
    static func overwrite(_ shares: [PendingShare]) throws {
        try SharedAppGroup.write(shares, to: SharedAppGroup.FileName.pendingShares)
    }
}
