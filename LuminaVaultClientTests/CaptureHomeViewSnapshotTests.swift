// LuminaVaultClient/LuminaVaultClientTests/CaptureHomeViewSnapshotTests.swift
//
// Home is the screen the redesign is about, so it gets pixels: the composer
// over a glance strip over what you saved, empty and populated, light and
// dark.
//
// Recording is ON in this suite. Baselines cannot be recorded on an Xcode
// 26.2 machine against CI's iOS 26.4 renderer, so CI writes them on the first
// run and Task 7 turns recording back off with the PNGs committed.

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
        isRecording = true
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        isRecording = false
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
        glance: HomeGlanceViewModel
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
    }

    private func snap(_ view: some View, _ name: String, dark: Bool) {
        assertSnapshot(
            of: view
                .environment(\.lvAmbientMotionEnabled, false)
                .environment(AppState())
                .environment(\.locale, Locale(identifier: "en_US"))
                .preferredColorScheme(dark ? .dark : .light),
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: dark ? .dark : .light)
            ),
            named: name
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
