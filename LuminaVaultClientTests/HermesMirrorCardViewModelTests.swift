// LuminaVaultClient/LuminaVaultClientTests/HermesMirrorCardViewModelTests.swift
//
// iOS had no caller for `mirror/status` or `mirror/sync` at all, so a user
// could link their Hermes, see a green "Connected" badge, and never learn
// that nothing had been imported. `lastStatus == .ok` with zero counts is
// exactly what a linked-but-unread Hermes looks like, so the card must not
// read "ok" as "fine".

@testable import LuminaVaultClient
import LuminaVaultShared
import XCTest

@MainActor
final class HermesMirrorCardViewModelTests: XCTestCase {
    private final class StubClient: HermesMirrorClientProtocol, @unchecked Sendable {
        var statusResult: Result<HermesMirrorStatusDTO, Error>
        var syncResult: Result<HermesMirrorStatusDTO, Error>
        private(set) var syncCount = 0

        init(status: HermesMirrorStatusDTO, sync: HermesMirrorStatusDTO? = nil) {
            statusResult = .success(status)
            syncResult = .success(sync ?? status)
        }

        func status() async throws -> HermesMirrorStatusDTO { try statusResult.get() }
        func sync(scope _: [HermesMirrorSyncScope]?) async throws -> HermesMirrorStatusDTO {
            syncCount += 1
            return try syncResult.get()
        }
    }

    private func status(
        skills: Int = 0,
        jobs: Int = 0,
        vaultFiles: Int = 0,
        sessions: Int = 0,
        vaultState: HermesMirrorVaultState = .absent,
        lastStatus: HermesMirrorSyncStatus = .ok
    ) -> HermesMirrorStatusDTO {
        HermesMirrorStatusDTO(
            transport: .remote,
            lastSyncAt: Date(timeIntervalSince1970: 1_756_800_000),
            lastStatus: lastStatus,
            skillsCount: skills,
            jobsCount: jobs,
            vaultFilesCount: vaultFiles,
            vaultState: vaultState,
            sessionsImported: sessions
        )
    }

    func testLoadSurfacesCounts() async {
        let vm = HermesMirrorCardViewModel(client: StubClient(status: status(skills: 94, jobs: 46)))
        await vm.load()
        XCTAssertEqual(vm.currentStatus?.skillsCount, 94)
        XCTAssertEqual(vm.currentStatus?.jobsCount, 46)
    }

    /// The exact shape of the reported bug: connected, "ok", nothing imported.
    func testOkWithZeroCountsIsNotTreatedAsFine() {
        XCTAssertFalse(status(lastStatus: .ok).hasMirroredAnything)
        XCTAssertTrue(status(skills: 1).hasMirroredAnything)
        XCTAssertTrue(status(sessions: 5).hasMirroredAnything)
        XCTAssertTrue(status(vaultFiles: 2).hasMirroredAnything)
    }

    func testSyncReportsWhatChanged() async {
        let client = StubClient(status: status(skills: 0, jobs: 0), sync: status(skills: 94, jobs: 46))
        let vm = HermesMirrorCardViewModel(client: client)
        await vm.load()
        await vm.sync()
        XCTAssertEqual(client.syncCount, 1)
        XCTAssertEqual(vm.lastSyncMessage, "+94 skills, +46 jobs")
        XCTAssertEqual(vm.currentStatus?.skillsCount, 94)
    }

    func testSyncThatChangesNothingSaysSo() async {
        let vm = HermesMirrorCardViewModel(client: StubClient(status: status(skills: 94, jobs: 46)))
        await vm.load()
        await vm.sync()
        XCTAssertEqual(vm.lastSyncMessage, "Already up to date.")
    }

    /// The message that would have saved this whole investigation.
    func testSyncThatImportsNothingPointsAtTheCredentials() async {
        let vm = HermesMirrorCardViewModel(client: StubClient(status: status()))
        await vm.load()
        await vm.sync()
        XCTAssertEqual(
            vm.lastSyncMessage,
            "Nothing came across. Check that the gateway URL and key are right."
        )
    }

    func testVaultSummaryReflectsState() {
        XCTAssertEqual(status(vaultState: .absent).vaultSummary, "No vault found")
        XCTAssertEqual(status(vaultFiles: 12, vaultState: .imported).vaultSummary, "12 files imported")
        XCTAssertEqual(status(vaultState: .created).vaultSummary, "Created by LuminaVault")
    }

    func testFailureSurfacesInsteadOfSilentlyEmptyingTheCard() async {
        let client = StubClient(status: status())
        client.statusResult = .failure(APIError.unauthorized)
        let vm = HermesMirrorCardViewModel(client: client)
        await vm.load()
        guard case let .failed(message) = vm.state else {
            return XCTFail("expected a failed state, got \(vm.state)")
        }
        XCTAssertEqual(message, "Session expired — sign in again.")
    }
}
