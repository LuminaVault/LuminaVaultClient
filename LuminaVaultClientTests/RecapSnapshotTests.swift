// LuminaVaultClient/LuminaVaultClientTests/RecapSnapshotTests.swift
//
// The recap sheet and the card it shares, light and dark.
//
// New suite, so its cases are quarantined until CI's `record-snapshots`
// workflow (`.github/workflows/ci.yml`, workflow_dispatch) has recorded the
// baselines on its iPhone 16 Pro / iOS 26.4 renderer — see
// `SnapshotQuarantine`. The render test at the bottom is not a snapshot and
// runs everywhere: it checks the share image is produced at all, at the size
// the share sheet is promised.

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient
@testable import LuminaVaultShared

@MainActor
final class RecapSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    // MARK: - Fixtures

    private var recap: MeRecapResponse {
        .fixture(
            totals: RecapTotalsDTO(captures: 14, learned: 5, asked: 9, reviewed: 3, activeDays: 6, streakDays: 4),
            previous: RecapTotalsDTO(captures: 11, learned: 5, asked: 12, reviewed: 0, activeDays: 4, streakDays: 2),
            daily: [
                RecapDayDTO(date: "2026-10-09", captures: 2, learned: 1, asked: 1, reviewed: 0),
                RecapDayDTO(date: "2026-10-10", captures: 0, learned: 0, asked: 0, reviewed: 0),
                RecapDayDTO(date: "2026-10-11", captures: 3, learned: 1, asked: 2, reviewed: 1),
                RecapDayDTO(date: "2026-10-12", captures: 1, learned: 0, asked: 3, reviewed: 0),
                RecapDayDTO(date: "2026-10-13", captures: 4, learned: 2, asked: 1, reviewed: 1),
                RecapDayDTO(date: "2026-10-14", captures: 2, learned: 0, asked: 1, reviewed: 0),
                RecapDayDTO(date: "2026-10-15", captures: 2, learned: 1, asked: 1, reviewed: 1),
            ],
            kinds: RecapKindsDTO(preference: 1, decision: 2, fact: 1, note: 1),
            highlights: [
                RecapHighlightDTO(
                    kind: .decision,
                    refId: "7C0E0B53-9A51-4F43-9B0C-2C1E6B0E0001",
                    title: "We ship on Tuesdays",
                    date: Date(timeIntervalSince1970: 1_760_428_800)
                ),
                RecapHighlightDTO(
                    kind: .achievement,
                    refId: "streak-3",
                    title: "Three days in a row",
                    date: Date(timeIntervalSince1970: 1_760_515_200)
                ),
            ]
        )
    }

    private func snap(_ view: some View, _ name: String, dark: Bool, layout: SwiftUISnapshotLayout) {
        assertSnapshot(
            of: view
                .environment(\.lvAmbientMotionEnabled, false)
                .environment(AppState())
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.lvPalette, LVTheme.cyanGold.palette(for: dark ? .dark : .light))
                .preferredColorScheme(dark ? .dark : .light),
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: layout,
                traits: .init(userInterfaceStyle: dark ? .dark : .light)
            ),
            testName: name
        )
    }

    // MARK: - Cases

    func testRecapSheet() throws {
        try SnapshotQuarantine.skipUnlessRecording()
        let client = MockRecapClient()
        let view = RecapSheet(
            viewModel: RecapViewModel(client: client, initial: recap),
            memoryClient: MockMemoryClient()
        )
        snap(view, "recap-sheet-light", dark: false, layout: .device(config: .iPhone13Pro))
        snap(view, "recap-sheet-dark", dark: true, layout: .device(config: .iPhone13Pro))
    }

    func testShareCard() throws {
        try SnapshotQuarantine.skipUnlessRecording()
        let card = RecapShareCard(recap: recap)
        // The card fixes its own scheme; light and dark must render the same.
        snap(card, "recap-share-card-light", dark: false, layout: .sizeThatFits)
        snap(card, "recap-share-card-dark", dark: true, layout: .sizeThatFits)
    }

    func testYourWeekStrip() throws {
        try SnapshotQuarantine.skipUnlessRecording()
        let view = List {
            Section("Today") {
                YourWeekStrip(recap: recap, onOpen: {})
            }
        }
        .frame(width: 390, height: 200)
        snap(view, "your-week-strip-light", dark: false, layout: .sizeThatFits)
        snap(view, "your-week-strip-dark", dark: true, layout: .sizeThatFits)
    }

    // MARK: - Render

    func testTheShareCardRendersAtThreeTimesItsWidth() throws {
        let image = try XCTUnwrap(RecapShareCard.render(recap))
        XCTAssertEqual(image.scale, 3)
        XCTAssertEqual(image.size.width, RecapShareCard.width, accuracy: 0.5)
        XCTAssertGreaterThan(image.size.height, 200, "header, numbers, chart and legend all drew")
    }
}
