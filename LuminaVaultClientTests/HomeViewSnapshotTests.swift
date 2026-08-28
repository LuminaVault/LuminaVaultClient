// LuminaVaultClient/LuminaVaultClientTests/HomeViewSnapshotTests.swift
//
// HER-244 — image snapshots for the OS Shell Home/Dashboard. Covers
// the populated, loading, and empty states in light + dark mode.
//
// Reference simulator: **iPhone 16 Pro** with iOS 18+ SDK. To record
// references, flip `isRecording = false` once, run the suite, then
// commit `__Snapshots__/`. Animations are disabled and perceptual
// precision is loose to keep snapshots determinstic across CI hosts.

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient
@testable import LuminaVaultShared

@MainActor
final class HomeViewSnapshotTests: XCTestCase {
    // Un-quarantined 2026-08-28. The 2026-07-18 skip was waiting for the
    // references to be re-recorded on the iOS 26 / Xcode 26.4 toolchain; they
    // now have been. `makeView` additionally pins `lvAmbientMotionEnabled`,
    // which is what the animated hero components gate their `repeatForever`
    // drift on, so consecutive renders agree.
    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)
        isRecording = false
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    private func makeViewModel(
        stats: HomeViewModel.CardState<DashboardStatsResponse> = .loaded(.stub(today: 7, total: 142, lastCompileAt: Date(timeIntervalSince1970: 1_715_000_000))),
        profile: HomeViewModel.CardState<DashboardProfileResponse> = .loaded(.stub()),
        tasks: HomeViewModel.CardState<[TaskDTO]> = .loaded([.stub(label: "Compiling vault", state: .running, progress: 0.4)]),
        insights: HomeViewModel.CardState<[InsightDTO]> = .loaded([
            .stub(headline: "You're writing more on Tuesdays."),
            .stub(headline: "Three notes link to \"deep work\".", section: .connections),
        ]),
        isOnline: Bool = true
    ) -> HomeViewModel {
        let vm = HomeViewModel(
            statsClient: MockDashboardStatsClient(),
            profileClient: MockDashboardProfileClient(),
            tasksClient: MockTasksClient(),
            insightsClient: MockInsightsClient(),
            healthClient: MockHealthClient(),
            compileViewModel: SyncAndLearnViewModel(client: MockKBCompileClient()),
            displayName: "Fernando"
        )
        vm.stats = stats
        vm.profile = profile
        vm.tasks = tasks
        vm.insights = insights
        vm.isOnline = isOnline
        return vm
    }

    private func makeView(_ vm: HomeViewModel) -> some View {
        HomeView(vm: vm, onAskLumina: {}, sessionsDestination: { AnyView(EmptyView()) }, tasksDestination: { AnyView(EmptyView()) }, insightsDestination: { AnyView(EmptyView()) }, serverConnectionDestination: { AnyView(EmptyView()) })
            .transaction { $0.disablesAnimations = true }
            // Freezes any `repeatForever` hero drift at frame zero — the
            // components gate on this, and `disablesAnimations` alone does not
            // reach an explicit `withAnimation` started from `onAppear`.
            .environment(\.lvAmbientMotionEnabled, false)
            // Required, not decorative: `HomeView`'s scroll carries
            // `.lvTabBarMinimizeOnScroll()`, whose modifier reads
            // `LVTabBarMinimizeState` from the environment and traps when it is
            // absent. Un-quarantining the suite is what surfaced that — every
            // case in here crashed on the first render, hidden until now
            // behind the skip.
            .environment(LVTabBarMinimizeState())
    }

    // MARK: - Populated

    func testHomePopulatedDarkMode() {
        let view = makeView(makeViewModel()).preferredColorScheme(.dark)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: .dark)
            ),
            named: "iPhone16Pro-populated-dark"
        )
    }

    func testHomePopulatedLightMode() {
        let view = makeView(makeViewModel()).preferredColorScheme(.light)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: .light)
            ),
            named: "iPhone16Pro-populated-light"
        )
    }

    // MARK: - Loading

    func testHomeLoadingDarkMode() {
        let view = makeView(makeViewModel(
            stats: .loading,
            tasks: .loading,
            insights: .loading
        )).preferredColorScheme(.dark)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: .dark)
            ),
            named: "iPhone16Pro-loading-dark"
        )
    }

    // MARK: - Empty + offline

    func testHomeEmptyOfflineDarkMode() {
        let view = makeView(makeViewModel(
            stats: .loaded(.empty),
            tasks: .loaded([]),
            insights: .loaded([]),
            isOnline: false
        )).preferredColorScheme(.dark)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: .dark)
            ),
            named: "iPhone16Pro-empty-offline-dark"
        )
    }
}
