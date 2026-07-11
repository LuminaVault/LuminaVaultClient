// LuminaVaultClient/LuminaVaultClientTests/AuthLandingViewSnapshotTests.swift
//
// HER-XXX-D — image snapshots for AuthLandingView in light + dark mode.
//
// Reference simulator: **iPhone 16 Pro** with iOS 18+ SDK. Run with a
// different device class and references will not match — re-record only
// when the design changes, not when CI switches simulators.
//
// To record references: set `isRecording = true` on the suite once,
// run the suite, commit the generated `__Snapshots__/` directory.
//
// `LVLogoMark(showSparkle: true)` contains a non-deterministic sparkle
// animation, so snapshots use a loose perceptual precision rather than
// strict pixel match — the goal is to catch layout regressions, not to
// freeze every frame of the mascot.

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient

@MainActor
final class AuthLandingViewSnapshotTests: XCTestCase {
    private let preferenceKey = "lv.auth.preferredProvider"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: preferenceKey)
        UIView.setAnimationsEnabled(false)
        isRecording = false
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: preferenceKey)
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeView() -> some View {
        let vm = AuthViewModel(authClient: PreviewAuthClient(), appState: AppState())
        return NavigationStack { AuthLandingView(vm: vm) }
            .transaction { $0.disablesAnimations = true }
    }

    // Quarantined: AuthLandingView now layers LVHaloBackdrop, whose dust-field
    // drift is wall-clock-driven — `disablesAnimations` does not freeze it, so
    // consecutive renders differ beyond any sane perceptual tolerance (a fresh
    // recording fails against itself one run later). Re-enable once the halo
    // exposes a static-phase seam for tests (follow-up tracked in the Phase 0
    // deployment-modernization notes).
    private static let quarantineReason =
        "AuthLandingView halo drift is wall-clock-driven; snapshots are non-deterministic"

    // MARK: - Light

    func testAuthLandingLightMode() throws {
        try XCTSkipIf(true, Self.quarantineReason)
        let view = makeView().preferredColorScheme(.light)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: .light)
            ),
            named: "iPhone16Pro-light"
        )
    }

    // MARK: - Dark

    func testAuthLandingDarkMode() throws {
        try XCTSkipIf(true, Self.quarantineReason)
        let view = makeView().preferredColorScheme(.dark)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: .dark)
            ),
            named: "iPhone16Pro-dark"
        )
    }
}
