// LuminaVaultClient/LuminaVaultClientTests/CaptureHomeViewSnapshotTests.swift
//
// Home is the screen the redesign is about, so it gets pixels: the composer
// over a glance strip over what you saved, empty and populated, light and
// dark.
//
// The glance strip's tiles read Saved / Streak / To revisit, so `makeGlance`'s
// `memoriesToday:` is the number under "Saved" — the section header above it
// is the one that says "Today".
//
// Baselines were recorded on CI's iPhone 16 Pro / iOS 26.4 renderer via the
// `record-snapshots` workflow (`.github/workflows/ci.yml`, workflow_dispatch)
// on 2026-09-17. Re-record the same way after an intentional render change;
// a one-off re-record goes through the per-assert `record:` parameter.

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient
@testable import LuminaVaultShared

@MainActor
final class CaptureHomeViewSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    // MARK: - Fixtures

    private static let spaceID = UUID(uuidString: "2C1E6B0E-0000-4000-8000-00000000000A")!

    private func file(
        path: String,
        createdAt: TimeInterval,
        metadata: VaultNoteMetadataDTO? = nil
    ) -> VaultFileDTO {
        VaultFileDTO(
            id: UUID(uuidString: "0B0B0B0B-\(String(format: "%04X", Int(createdAt) % 0xFFFF))-4000-8000-00000000000B")!,
            path: path,
            contentType: "text/markdown",
            sizeBytes: 2_048,
            sha256: "deadbeef",
            spaceId: Self.spaceID,
            createdAt: Date(timeIntervalSince1970: createdAt),
            metadata: metadata
        )
    }

    private func makeViewModel(files: [VaultFileDTO]) async -> CaptureHomeViewModel {
        let vaultClient = MockVaultClient()
        vaultClient.listFilesResult = .success(
            VaultFileListResponse(files: files, limit: 20, nextBefore: nil)
        )
        let vm = CaptureHomeViewModel(queue: nil, drainer: .noop, vaultClient: vaultClient)
        await vm.loadFeed()
        return vm
    }

    private func makeGlance(
        memoriesToday: Int,
        streakDays: Int,
        toRevisit: Int,
        pendingFiles: Int
    ) async -> HomeGlanceViewModel {
        let summaryClient = MockHomeSummaryClient()
        summaryClient.result = .success(
            HomeSummaryResponse(
                skillsCount: 0, jobsCount: 0, remindersCount: 0,
                todosCount: 0, projectsCount: 0, insightsCount: 0,
                memoriesToday: memoriesToday,
                streakDays: streakDays
            )
        )
        let kbClient = MockKBCompileClient()
        kbClient.pendingResult = .success(KBCompilePendingResponse(pendingFiles: pendingFiles))

        let vm = HomeGlanceViewModel(
            homeClient: summaryClient,
            dailyReviewClient: MockDailyReviewClient(memories: toRevisit),
            pendingClient: kbClient
        )
        await vm.load()
        return vm
    }

    private func makeView(
        vm: CaptureHomeViewModel,
        glance: HomeGlanceViewModel,
        guided: GuidedStartCoordinator? = nil
    ) -> some View {
        NavigationStack {
            CaptureHomeView(
                vm: vm,
                vaultClient: MockVaultClient(),
                memoryClient: InertMemoryClient(),
                glance: glance,
                onOpenSettings: {}
            )
        }
        // Home reads the coordinator out of the environment, so `nil` is what
        // the three cases above render: Home exactly as it was before the
        // wizard existed. Their baselines are therefore unchanged — the
        // composer's new anchor is a preference and moves no pixels.
        .environment(guided)
    }

    /// A coordinator with the latches a fresh account has and no network
    /// underneath it. Nothing here polls: the card's render only reads
    /// `progress`, `hermieState` and `inlineMessage`.
    private func makeGuided(
        state: OnboardingStateDTO,
        dismissed: Bool = false
    ) -> GuidedStartCoordinator {
        GuidedStartCoordinator(
            client: GuidedStartCoordinatorTests.ScriptedOnboardingClient([state]),
            telemetry: GuidedStartTelemetry(
                client: ConversionFunnelTelemetryTests.FakePostHogClient()
            ),
            snapshot: { state },
            applySnapshot: { _ in },
            pendingCaptureCount: { 0 },
            isDismissed: { dismissed },
            setDismissed: { _ in }
        )
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

    func testPopulated() async {
        let vm = await makeViewModel(files: [
            file(path: "notes/2026-09-14-161709-quarterly-plan-00e2c497.md", createdAt: 1_757_865_429),
            file(
                path: "links/2026-09-14-161709-kheprios-com-00e2c498.md",
                createdAt: 1_757_861_429,
                metadata: VaultNoteMetadataDTO(enrichmentStatus: "pending")
            ),
            file(
                path: "notes/dentist.md",
                createdAt: 1_757_761_429,
                metadata: VaultNoteMetadataDTO(title: "Dentist moved to Thursday")
            ),
        ])
        let glance = await makeGlance(memoriesToday: 7, streakDays: 3, toRevisit: 0, pendingFiles: 0)
        snap(makeView(vm: vm, glance: glance), "home-populated-light", dark: false)
        snap(makeView(vm: vm, glance: glance), "home-populated-dark", dark: true)
    }

    func testEmpty() async {
        let vm = await makeViewModel(files: [])
        let glance = await makeGlance(memoriesToday: 0, streakDays: 0, toRevisit: 0, pendingFiles: 0)
        snap(makeView(vm: vm, glance: glance), "home-empty-light", dark: false)
        snap(makeView(vm: vm, glance: glance), "home-empty-dark", dark: true)
    }

    func testWithRecommendation() async {
        let vm = await makeViewModel(files: [
            file(path: "notes/dentist.md", createdAt: 1_757_761_429)
        ])
        let glance = await makeGlance(memoriesToday: 2, streakDays: 11, toRevisit: 4, pendingFiles: 6)
        snap(makeView(vm: vm, glance: glance), "home-recommendation-light", dark: false)
        snap(makeView(vm: vm, glance: glance), "home-recommendation-dark", dark: true)
    }

    // MARK: - Guided start

    /// The first thing a new account sees: an empty vault, and the
    /// get-started card at the top of Today. This is the render that says
    /// the wizard is actually mounted rather than merely compiled — the app
    /// cannot sign in on this simulator, so a device-size snapshot is the
    /// evidence, not a walkthrough.
    ///
    /// No baseline yet, so it is quarantined. The PNGs come from the
    /// `record-snapshots` workflow, same as every other baseline here.
    func testGuidedStartCardOnAFreshAccount() async throws {
        try SnapshotQuarantine.skipUnlessRecording()
        let vm = await makeViewModel(files: [])
        let glance = await makeGlance(memoriesToday: 0, streakDays: 0, toRevisit: 0, pendingFiles: 0)
        let guided = makeGuided(state: makeStepState())
        snap(
            makeView(vm: vm, glance: glance, guided: guided),
            "home-guided-start-light",
            dark: false
        )
        snap(
            makeView(vm: vm, glance: glance, guided: guided),
            "home-guided-start-dark",
            dark: true
        )
    }

    /// Two steps in, with a Sync & Learn recommendation underneath — the
    /// card and the rest of Today sharing the section, which is the layout
    /// most likely to go wrong.
    func testGuidedStartCardAboveARecommendation() async throws {
        try SnapshotQuarantine.skipUnlessRecording()
        let vm = await makeViewModel(files: [
            file(path: "notes/dentist.md", createdAt: 1_757_761_429)
        ])
        let glance = await makeGlance(memoriesToday: 2, streakDays: 1, toRevisit: 0, pendingFiles: 6)
        let guided = makeGuided(state: makeStepState(capture: true))
        snap(
            makeView(vm: vm, glance: glance, guided: guided),
            "home-guided-start-recommendation-light",
            dark: false
        )
        snap(
            makeView(vm: vm, glance: glance, guided: guided),
            "home-guided-start-recommendation-dark",
            dark: true
        )
    }

    /// A dismissed card is no card: Home goes back to exactly what the three
    /// cases above render, which is also what lets the breaking-news strip
    /// return. The assertion is on the visibility predicate rather than on
    /// pixels, because "renders nothing" has no baseline to compare.
    func testDismissedCardHidesItselfAndReleasesTheNewsStrip() async {
        let visible = makeGuided(state: makeStepState())
        let dismissed = makeGuided(state: makeStepState(), dismissed: true)
        XCTAssertTrue(visible.isCardVisible)
        XCTAssertFalse(dismissed.isCardVisible)
    }
}

/// Reading is the vault's job and no snapshot here opens the reader.
private struct InertMemoryClient: MemoryClientProtocol {
    func upsert(_: MemoryUpsertRequest) async throws -> MemoryUpsertResponse {
        throw APIError.unauthorized
    }

    func get(id _: UUID) async throws -> MemoryDTO {
        throw APIError.unauthorized
    }

    func patch(id _: UUID, _: MemoryPatchRequest) async throws -> MemoryDTO {
        throw APIError.unauthorized
    }

    func list(limit _: Int, offset _: Int) async throws -> MemoryListResponse {
        throw APIError.unauthorized
    }

    func search(_: MemorySearchRequest) async throws -> MemorySearchResponse {
        throw APIError.unauthorized
    }

    func delete(id _: UUID) async throws {
        throw APIError.unauthorized
    }
}
