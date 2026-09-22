// LuminaVaultClient/LuminaVaultClient/Features/Shell/ShellActivity.swift
//
// Agent runs still working somewhere other than the screen you are on.
//
// An escalated chat turn runs on the server and keeps streaming into a
// follower on the AI tab. Switch to Brain and nothing says it is still going.
// This is the registry the shell reads to say so. The same idea as the web
// client's `src/lib/shell/status.svelte.ts`.
//
// Deliberately dumb. The chat view model registers and deregisters, because
// it owns the follower's lifetime. `begin` is idempotent on run id: a
// follower that reconnects resumes the same run and must not read as a second
// agent. Deregistration is the sharp edge — every path that drops a follower
// has to end its run here, or the banner claims an agent is working forever.

import Foundation
import Observation

@Observable
@MainActor
final class ShellActivity {
    private(set) var runIDs: [UUID] = []

    var busy: Bool { !runIDs.isEmpty }

    func begin(_ runID: UUID) {
        guard !runIDs.contains(runID) else { return }
        runIDs.append(runID)
    }

    func end(_ runID: UUID) {
        runIDs.removeAll { $0 == runID }
    }

    func clear() {
        runIDs = []
    }
}
