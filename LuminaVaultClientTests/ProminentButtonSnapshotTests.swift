// LuminaVaultClient/LuminaVaultClientTests/ProminentButtonSnapshotTests.swift
//
// `.lvProminent` in the states that take different colours: palette pair when
// enabled, system colours when disabled, system red when destructive.
//
// The canvas is small and the precision high on purpose. A label colour change
// is too few pixels to fail the 0.98 precision a full-screen snapshot uses.
//
// Baselines come from the `record-snapshots` workflow, as for every suite here.
// Cases are `async` because of the repo-wide synchronous `@MainActor` test abort
// described in GuidedStartCardSnapshotTests.

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient

@MainActor
final class ProminentButtonSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    func testStatesDark() async {
        snap(dark: true)
    }

    func testStatesLight() async {
        snap(dark: false)
    }

    private func snap(dark: Bool, testName: String = #function) {
        let view = VStack(spacing: LVSpacing.base) {
            Button("Share recap") {}
                .buttonStyle(.lvProminent)
            Button {} label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.lvProminent)
            Button("Disabled") {}
                .buttonStyle(.lvProminent)
                .disabled(true)
            Button("Permanently delete", role: .destructive) {}
                .buttonStyle(.lvProminent)
            Button("Deny") {}
                .buttonStyle(.lvProminent(destructive: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.lvPalette, LVTheme.cyanGold.palette(for: dark ? .dark : .light))
        .preferredColorScheme(dark ? .dark : .light)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.995,
                perceptualPrecision: 0.98,
                layout: .fixed(width: 320, height: 320),
                traits: .init(userInterfaceStyle: dark ? .dark : .light)
            ),
            testName: testName
        )
    }
}
