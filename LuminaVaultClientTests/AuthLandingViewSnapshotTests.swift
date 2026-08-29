// LuminaVaultClient/LuminaVaultClientTests/AuthLandingViewSnapshotTests.swift
//
// HER-XXX-D — image snapshots for AuthLandingView in light + dark mode.
//
// Reference simulator: **iPhone 16 Pro** with iOS 18+ SDK. Run with a
// different device class and references will not match — re-record only
// when the design changes, not when CI switches simulators. `ci.yml` pins
// the same device for that reason.
//
// To record references: set `isRecording = true` on the suite once,
// run the suite, commit the generated `__Snapshots__/` directory.
//
// `LVLogoMark(showSparkle: true)` embeds a `SparkleField`, whose drift is
// driven by absolute wall-clock. It happens to be inert here already —
// `scenePhase` is not `.active` under the test host — but that is an
// accident of the harness, not a guarantee, so `SparkleField` now also gates
// on `\.lvAmbientMotionEnabled` (which these fixtures set) alongside the halo
// and the breathing glow. Re-recording produces byte-identical PNGs.
//
// The loose precision below therefore absorbs rasterization noise only. It is
// deliberately not wide enough to hide a row appearing or disappearing.

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

    // Un-quarantined 2026-08-28. The suite was skipped because
    // `LVHaloBackdrop`'s dust drift and `LVLogoMark`'s breathing glow survived
    // `disablesAnimations` — both are `repeatForever` animations started from
    // `onAppear`, which that flag does not reach — so two consecutive captures
    // caught them at different phases and a fresh recording failed against
    // itself one run later.
    //
    // `\.lvAmbientMotionEnabled` is the static-phase seam the old note asked
    // for. `accessibilityReduceMotion`, which both components already gate on,
    // is get-only on `EnvironmentValues` and so cannot be set from a test.
    //
    // The provider list is pinned rather than inherited. `AuthProviderOption
    // .configured` — the production default — drops the Google and X rows
    // unless the build carries their client IDs, and those arrive from a
    // gitignored xcconfig. A developer machine holding real secrets rendered
    // five rows while CI, which materializes the `.sample` placeholders,
    // rendered four; the whole stack below the missing row shifted up and
    // 8.75% of the frame disagreed. That is a difference in *what was
    // rendered*, not in how it rasterized, so no precision tolerance is the
    // right answer for it. `allCases` is the superset, so these images assert
    // every row's layout and render identically on every machine.
    private func makeView() -> some View {
        let vm = AuthViewModel(authClient: PreviewAuthClient(), appState: AppState())
        return NavigationStack { AuthLandingView(vm: vm, visibleProviders: AuthProviderOption.allCases) }
            .transaction { $0.disablesAnimations = true }
            .environment(\.lvAmbientMotionEnabled, false)
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
