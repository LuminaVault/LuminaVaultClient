// LuminaVaultClient/LuminaVaultClientTests/LearnedThisWeekSnapshotTests.swift
//
// "What I learned this week": the sheet with both sections, its empty
// state, and Home's "Confirm what I learned" row, light and dark.
//
// New suite, so its cases are quarantined until CI's `record-snapshots`
// workflow (`.github/workflows/ci.yml`, workflow_dispatch) has recorded the
// baselines on its iPhone 16 Pro / iOS 26.4 renderer — see
// `SnapshotQuarantine`.

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient
@testable import LuminaVaultShared

@MainActor
final class LearnedThisWeekSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    private func loadedViewModel(_ digest: LearnedDigestResponse) async -> LearnedThisWeekViewModel {
        let vm = LearnedThisWeekViewModel(
            client: MockLearnedClient(digest),
            memoryClient: MockMemoryClient(),
            improvementClient: MockSelfImprovementClient()
        )
        await vm.load()
        return vm
    }

    private func snap(_ view: some View, _ name: String, dark: Bool, layout: SwiftUISnapshotLayout) {
        assertSnapshot(
            of: view
                .environment(\.lvAmbientMotionEnabled, false)
                .environment(AppState())
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, .gmt)
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

    func testSheet() async throws {
        try SnapshotQuarantine.skipUnlessRecording()
        let view = LearnedThisWeekSheet(viewModel: await loadedViewModel(.fixture()), memoryClient: MockMemoryClient())
        snap(view, "learned-sheet-light", dark: false, layout: .device(config: .iPhone13Pro))
        snap(view, "learned-sheet-dark", dark: true, layout: .device(config: .iPhone13Pro))
    }

    func testEmptySheet() async throws {
        try SnapshotQuarantine.skipUnlessRecording()
        let view = LearnedThisWeekSheet(viewModel: await loadedViewModel(.empty), memoryClient: MockMemoryClient())
        snap(view, "learned-sheet-empty-light", dark: false, layout: .device(config: .iPhone13Pro))
        snap(view, "learned-sheet-empty-dark", dark: true, layout: .device(config: .iPhone13Pro))
    }

    func testHomeRow() async throws {
        try SnapshotQuarantine.skipUnlessRecording()
        let view = List {
            Section("Today") {
                LearnedHomeRow(count: 4, onOpen: {})
            }
        }
        .frame(width: 390, height: 160)
        snap(view, "learned-home-row-light", dark: false, layout: .sizeThatFits)
        snap(view, "learned-home-row-dark", dark: true, layout: .sizeThatFits)
    }
}
