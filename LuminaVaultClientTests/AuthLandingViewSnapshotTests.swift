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

    // MARK: - Light

    func testAuthLandingLightMode() {
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

    func testAuthLandingDarkMode() {
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
