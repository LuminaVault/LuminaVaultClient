// LuminaVaultClient/LuminaVaultClientTests/GuidedStartCardSnapshotTests.swift
//
// "Get started with Hermie" at every progress it can reach: nothing done,
// one done, two done, and the finished card with its completion line.
// 4 cases × 2 schemes = 8 baselines.
//
// The card is pure presentation — a `GuidedStartProgress` and two closures —
// so there is no view model, no client and no network here. The snapshot is
// of exactly what Home will embed.
//
// No baselines yet, so every case is behind
// `SnapshotQuarantine.skipUnlessRecording()`: skipped on an ordinary run,
// executed (and recorded) when `SNAPSHOT_TESTING_RECORD` is set. This suite
// never touches the process-global `isRecording` — a suite that flips it
// changes what every later suite in the run does.
//
// Baselines cannot be recorded on this machine against CI's iOS 26.4
// renderer, so they come from the `record-snapshots` workflow
// (`.github/workflows/ci.yml`, workflow_dispatch). Commit the PNGs from its
// `snapshots-<sha>` artifact, then delete the `skipUnlessRecording()` calls.
// A one-off re-record goes through the per-assert `record:` parameter.
//
// Every case is `async` on purpose: this toolchain aborts
// (`malloc: pointer being freed was not allocated`) on a *synchronous* test
// method in a `@MainActor` XCTestCase, repo-wide and unrelated to this code.

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient
@testable import LuminaVaultShared

@MainActor
final class GuidedStartCardSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    // MARK: - Harness

    /// Home hosts the card on the grouped background, so the snapshot does
    /// too — a card on a white page would not show whether the
    /// `secondarySystemGroupedBackground` surface reads against its ground.
    private func makeView(
        progress: GuidedStartProgress,
        hermie: HermieMascotState
    ) -> some View {
        VStack(spacing: 0) {
            GuidedStartCard(
                progress: progress,
                hermieState: hermie,
                onSelect: { _ in },
                onDismiss: {}
            )
            .padding(LVSpacing.base)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        // `lvPulse` on the next row is a `repeatForever` started from
        // `onAppear`, which `disablesAnimations` does not reach. Without this
        // the same state captures at two different scales.
        .environment(\.lvAmbientMotionEnabled, false)
    }

    private func snap(_ view: some View, _ name: String, dark: Bool) {
        assertSnapshot(
            of: view
                .environment(\.lvAmbientMotionEnabled, false)
                .environment(AppState())
                .environment(\.locale, Locale(identifier: "en_US"))
                // The app resolves the palette per colour scheme through
                // `LVThemeManager`; without one the environment default is the
                // dark palette, which renders light-mode text nearly white.
                .environment(\.lvPalette, LVTheme.cyanGold.palette(for: dark ? .dark : .light))
                .preferredColorScheme(dark ? .dark : .light),
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: dark ? .dark : .light)
            ),
            // `testName` rather than `named`, so the baseline is called what
            // the case is called instead of carrying this helper's signature
            // and a misleading "dark" into every file name.
            testName: name
        )
    }

    // MARK: - Cases

    /// A fresh account: all three latches false, the first row pulsing.
    func testNothingDone() async throws {
        try SnapshotQuarantine.skipUnlessRecording()
        let progress = GuidedStartProgress(makeStepState())
        snap(makeView(progress: progress, hermie: .idle), "guided-card-0of3-light", dark: false)
        snap(makeView(progress: progress, hermie: .idle), "guided-card-0of3-dark", dark: true)
    }

    func testOneDone() async throws {
        try SnapshotQuarantine.skipUnlessRecording()
        let progress = GuidedStartProgress(makeStepState(capture: true))
        snap(makeView(progress: progress, hermie: .idle), "guided-card-1of3-light", dark: false)
        snap(makeView(progress: progress, hermie: .idle), "guided-card-1of3-dark", dark: true)
    }

    func testTwoDone() async throws {
        try SnapshotQuarantine.skipUnlessRecording()
        let progress = GuidedStartProgress(makeStepState(capture: true, compile: true))
        snap(makeView(progress: progress, hermie: .idle), "guided-card-2of3-light", dark: false)
        snap(makeView(progress: progress, hermie: .idle), "guided-card-2of3-dark", dark: true)
    }

    /// The finished card: every row checked, the completion line, and Hermie
    /// celebrating. The visibility rule hides this card at the next refresh —
    /// it is on screen only for the celebration and for Settings ›
    /// "Show me around" — so it is worth a baseline of its own.
    func testAllDone() async throws {
        try SnapshotQuarantine.skipUnlessRecording()
        let progress = GuidedStartProgress(makeStepState(capture: true, compile: true, query: true))
        snap(
            makeView(progress: progress, hermie: .celebrating),
            "guided-card-3of3-light",
            dark: false
        )
        snap(
            makeView(progress: progress, hermie: .celebrating),
            "guided-card-3of3-dark",
            dark: true
        )
    }
}
