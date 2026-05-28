// LuminaVaultClient/LuminaVaultClientTests/SkillsHubViewSnapshotTests.swift
//
// HER-263 — image snapshots for the OS Shell Skills hub. Populated dark
// + light + loading dark variants. Mirrors HomeViewSnapshotTests.

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient
@testable import LuminaVaultShared

@MainActor
final class SkillsHubViewSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)
        isRecording = false
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    // MARK: - Fixtures

    private final class StubSkillsClient: SkillsClientProtocol, @unchecked Sendable {
        let listResult: Result<SkillListResponse, Error>
        init(listResult: Result<SkillListResponse, Error>) { self.listResult = listResult }
        func list() async throws -> SkillListResponse { try listResult.get() }
        func patch(name: String, body: SkillPatchRequest) async throws -> LuminaVaultShared.SkillDTO {
            throw APIError.networkFailure(URLError(.timedOut))
        }
        func runs(name: String, limit: Int?) async throws -> SkillRunsResponse {
            SkillRunsResponse(runs: [], sparkline: [], nextCursor: nil)
        }
        func run(name: String, request: SkillRunRequest) async throws -> SkillRunResponse {
            throw APIError.networkFailure(URLError(.timedOut))
        }
    }

    private static func stubSkill(
        name: String,
        source: SkillSource = .builtin,
        enabled: Bool = true,
        lastStatus: SkillRunStatus? = .success
    ) -> LuminaVaultShared.SkillDTO {
        LuminaVaultShared.SkillDTO(
            id: "\(source.rawValue):\(name)",
            source: source,
            name: name,
            title: name,
            descriptionText: "Short description of what \(name) does in the background.",
            capability: .medium,
            schedule: "0 7 * * *",
            scheduleOverride: nil,
            enabled: enabled,
            lastRunAt: Date(timeIntervalSince1970: 1_715_000_000),
            lastStatus: lastStatus,
            lastError: nil,
            dailyRunCount: 2,
            dailyRunCap: 10,
            apnsCategory: .digest,
            bodyExcerpt: "## Trigger\nRuns daily at 7am and emits a digest push."
        )
    }

    private func makeView(state: SkillsHubViewModel.LoadState) -> some View {
        let canned: [LuminaVaultShared.SkillDTO] = state == .loaded ? [
            Self.stubSkill(name: "daily-brief"),
            Self.stubSkill(name: "weekly-memo"),
            Self.stubSkill(name: "pattern-detector"),
            Self.stubSkill(name: "kb-compile", enabled: false, lastStatus: .error),
        ] : []
        let client = StubSkillsClient(listResult: .success(SkillListResponse(skills: canned)))
        let vm = SkillsHubViewModel(client: client)
        vm.skills = canned
        vm.state = state
        return NavigationStack {
            SkillsHubView(vm: vm, detailClient: client)
        }
        .transaction { $0.disablesAnimations = true }
    }

    // MARK: - Cases

    func testSkillsHubPopulatedDarkMode() {
        let view = makeView(state: .loaded).preferredColorScheme(.dark)
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

    func testSkillsHubPopulatedLightMode() {
        let view = makeView(state: .loaded).preferredColorScheme(.light)
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

    func testSkillsHubLoadingDarkMode() {
        let view = makeView(state: .loading).preferredColorScheme(.dark)
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
}
