// LuminaVaultClient/LuminaVaultClientTests/HermesMirrorJobsViewSnapshotTests.swift
//
// Hermes Companion Phase 2 — image snapshots for the mirror job surfaces.
// Recorded on the iPhone 16 Pro simulator CI pins.

@testable import LuminaVaultClient
@testable import LuminaVaultShared
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@MainActor
final class HermesMirrorJobsViewSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)
        isRecording = false
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    func testJobsListSeparatesScheduledFromPaused() {
        let client = StubHermesMirrorJobsClient()
        let vm = HermesMirrorJobsListViewModel(
            client: client,
            jobs: [
                .stub(id: "morning-brief", name: "Morning brief", schedule: "0 7 * * *", lastRunAt: Self.ago(65 * 60)),
                .stub(id: "index-rebuild", name: "Rebuild index", schedule: "every 6h", lastRunAt: Self.ago(20 * 60)),
                .stub(id: "weekly-memo", name: "Weekly memo", schedule: "0 9 * * 1", paused: true),
            ]
        )
        snap(
            NavigationStack { HermesMirrorJobsView(vm: vm, client: client) },
            named: "iPhone16Pro-mirror-jobs-dark"
        )
    }

    func testJobDetailShowsTheCollectedOutput() {
        let client = StubHermesMirrorJobsClient()
        let vm = HermesMirrorJobDetailViewModel(
            client: client,
            job: .stub(
                id: "morning-brief",
                name: "Morning brief",
                schedule: "0 7 * * *",
                prompt: "Summarise overnight mail and anything new in the vault.",
                lastRunAt: Self.ago(65 * 60),
                nextRunAt: Self.ago(-3 * 60 * 60)
            ),
            runs: [
                .stub(
                    key: "run-3",
                    status: .ok,
                    output: "**Overnight**\nThree new threads, none urgent. The deploy finished at 03:12.",
                    startedAt: Self.fixed(1_757_000_000),
                    vaultFilePath: "raw/jobs/morning-brief/2026-09-04.md",
                    tokens: HermesJobRunTokensDTO(input: 1_820, output: 240)
                ),
                .stub(key: "run-2", status: .error, error: "hermes unreachable", startedAt: Self.fixed(1_756_913_600)),
                .stub(key: "run-1", status: .ok, output: "Quiet night.", startedAt: Self.fixed(1_756_827_200)),
            ]
        )
        snap(
            NavigationStack { HermesMirrorJobDetailView(vm: vm, client: client) },
            named: "iPhone16Pro-mirror-job-detail-dark"
        )
    }

    func testJobEditorPrefillsTheJobBeingEdited() {
        let client = StubHermesMirrorJobsClient()
        let vm = HermesMirrorJobEditorViewModel(
            client: client,
            mode: .edit(
                .stub(
                    id: "morning-brief",
                    name: "Morning brief",
                    schedule: "0 7 * * *",
                    prompt: "Summarise overnight mail and anything new in the vault."
                )
            )
        )
        snap(
            NavigationStack { HermesMirrorJobEditorView(vm: vm, onSaved: { _ in }) },
            named: "iPhone16Pro-mirror-job-editor-dark"
        )
    }

    // MARK: - Helper

    /// Relative dates are anchored to now, not to a fixed epoch, so the
    /// rendered wording ("1 hour ago") cannot drift as the calendar moves.
    private static func ago(_ seconds: TimeInterval) -> Date {
        Date().addingTimeInterval(-seconds)
    }

    /// Absolute timestamps (the run cards) need a fixed instant, not a
    /// now-anchored one: "Fri, Sep 4 at 21:06" would be re-rendered
    /// differently tomorrow and invalidate the baseline daily.
    private static func fixed(_ epoch: TimeInterval) -> Date {
        Date(timeIntervalSince1970: epoch)
    }

    private func snap(_ view: some View, named: String) {
        assertSnapshot(
            of: view
                .transaction { $0.disablesAnimations = true }
                .environment(\.lvAmbientMotionEnabled, false)
                // Absolute timestamps render through the environment's
                // locale/calendar/time zone, so both are pinned: an
                // unpinned baseline recorded here would not match a CI
                // runner sitting in UTC.
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.calendar, Calendar(identifier: .gregorian))
                .environment(\.timeZone, TimeZone(secondsFromGMT: 0) ?? .current),
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: .dark)
            ),
            named: named
        )
    }
}
