// LuminaVaultClient/LuminaVaultClientTests/SnapshotQuarantine.swift
//
// The guard a snapshot suite wears until its baselines exist.
//
// This file was introduced for the fourteen suites the native shell
// (ADR 0001) re-grounded, and deleted on 2026-09-17 once their PNGs were
// committed. It comes back for the same reason it existed: a brand-new suite
// has no baselines, and they cannot be recorded here — the baselines belong
// to CI's Xcode 26.4 / iOS 26.4 renderer, produced by the `record-snapshots`
// workflow (`.github/workflows/ci.yml`, workflow_dispatch).
//
// That leaves one job with two opposite behaviours: an ordinary PR run must
// not fail on baselines that do not exist yet, and the record run must
// actually execute the cases so there is something to record. A plain
// `XCTSkipIf(true, …)` satisfies the first and breaks the second — a skipped
// case renders nothing and writes no PNG.
//
// So the skip keys off the same environment variable that puts
// swift-snapshot-testing into record mode. No variable: skip, and PR CI stays
// green. Variable set: run, render, record.

import Foundation
import XCTest

enum SnapshotQuarantine {
    /// Set by the `record-snapshots` workflow, and read natively by
    /// swift-snapshot-testing (1.16+) to turn recording on. Reading the same
    /// key here is what keeps the skip and the record mode from disagreeing.
    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"] != nil
    }

    /// Skips unless the run is a recording run.
    ///
    /// Call as the first line of a quarantined case. Remove the call — not
    /// the environment variable — once the case's baseline is committed.
    static func skipUnlessRecording(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try XCTSkipIf(
            !isRecording,
            "Quarantined: run the record-snapshots workflow, commit the PNGs it uploads, then remove this skip",
            file: file,
            line: line
        )
    }
}
