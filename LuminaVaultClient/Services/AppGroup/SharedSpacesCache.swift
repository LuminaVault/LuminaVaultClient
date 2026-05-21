// LuminaVaultClient/LuminaVaultClient/Services/AppGroup/SharedSpacesCache.swift
//
// HER-258 — main app writes the user's Spaces into the App Group so the
// Share Extension can populate its picker without making a network call.
// The extension only reads (via `SharedAppGroup.read` directly, so the
// extension target doesn't pull in this file or `LuminaVaultShared`).
//
// **Target membership: LuminaVaultClient only** — see HER-258 PR notes.

import Foundation
import LuminaVaultShared

enum SharedSpacesCache {
    /// Snapshot the live Spaces list to the App Group. Called by the
    /// main app on launch (post-auth) and after any Spaces mutation
    /// (create / rename / delete). No-op when the App Group container
    /// isn't provisioned (entitlement missing on a sideloaded build).
    static func write(_ spaces: [SpaceDTO]) {
        let summaries = spaces.map { SharedSpaceSummary(id: $0.id, name: $0.name) }
        try? SharedAppGroup.write(summaries, to: SharedAppGroup.FileName.spacesCache)
    }

    /// Read the latest Spaces snapshot. Available in the main app for
    /// debugging; the extension uses `SharedAppGroup.read` directly.
    static func read() -> [SharedSpaceSummary]? {
        SharedAppGroup.read([SharedSpaceSummary].self, from: SharedAppGroup.FileName.spacesCache)
    }
}
