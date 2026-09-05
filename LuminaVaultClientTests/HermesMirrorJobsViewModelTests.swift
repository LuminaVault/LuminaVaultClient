// LuminaVaultClient/LuminaVaultClientTests/HermesMirrorJobsViewModelTests.swift
//
// Hermes Companion Phase 2 — job control and the collected run history.
//
// The behaviour worth guarding hardest is the editor's partial update. The
// server forwards whatever it is given to Hermes as `updates`, and this
// editor only shows five of a job's thirteen fields — so sending the whole
// form back would blank the model, provider, toolsets and workdir the user
// set up on the machine itself.

import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

@MainActor
final class HermesMirrorJobsViewModelTests: XCTestCase {
    private var client: StubHermesMirrorJobsClient!

    override func setUp() async throws {
        try await super.setUp()
        client = StubHermesMirrorJobsClient()
    }

    // MARK: - List

    func testJobsSplitIntoScheduledAndPaused() async {
        client.jobsResult = .success(
            HermesMirroredJobsResponse(
                source: .live,
                jobs: [
                    .stub(id: "morning-brief"),
                    .stub(id: "weekly-memo", paused: true),
                    .stub(id: "index-rebuild"),
                ]
            )
        )
        let sut = HermesMirrorJobsListViewModel(client: client)

        await sut.load()

        XCTAssertEqual(sut.active.map(\.hermesJobID), ["morning-brief", "index-rebuild"])
        XCTAssertEqual(sut.paused.map(\.hermesJobID), ["weekly-memo"])
        XCTAssertEqual(sut.source, .live)
    }

    /// `snapshot` means Hermes was unreachable and the rows are the last
    /// synced copy — the screen has to be able to say so.
    func testSnapshotSourceIsCarriedThrough() async {
        client.jobsResult = .success(
            HermesMirroredJobsResponse(source: .snapshot, jobs: [.stub(id: "morning-brief")])
        )
        let sut = HermesMirrorJobsListViewModel(client: client)

        await sut.load()

        XCTAssertEqual(sut.source, .snapshot)
    }

    func testAnUnlinkedHermesIsItsOwnFailureNotAGenericOne() async {
        client.jobsResult = .failure(Self.failure(409, "hermes_mirror_not_configured"))
        let sut = HermesMirrorJobsListViewModel(client: client)

        await sut.load()

        XCTAssertEqual(sut.state, .failed(.notConfigured))
        // Retrying cannot help — the user has to link a Hermes.
        XCTAssertFalse(HermesMirrorFailure.notConfigured.isRetryable)
        XCTAssertNotNil(HermesMirrorFailure.notConfigured.guidance)
    }

    // MARK: - Detail

    func testRunHistoryLoadsAndSplitsLatestFromTheRest() async {
        client.runsResult = .success(
            HermesJobRunsResponse(
                hermesJobID: "morning-brief",
                runs: [
                    .stub(key: "run-3", status: .ok, output: "newest"),
                    .stub(key: "run-2", status: .error, error: "boom"),
                    .stub(key: "run-1", status: .ok, output: "oldest"),
                ],
                collectedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        let sut = HermesMirrorJobDetailViewModel(client: client, job: .stub(id: "morning-brief"))

        await sut.load()

        XCTAssertEqual(sut.state, .loaded)
        XCTAssertEqual(sut.latest?.runKey, "run-3")
        XCTAssertEqual(sut.history.map(\.runKey), ["run-2", "run-1"])
        XCTAssertNotNil(sut.collectedAt)
    }

    /// The screen reads stored rows, so it stays useful when the machine is
    /// offline — a failed *control* must not take the history down with it.
    func testAFailedControlLeavesTheHistoryOnScreen() async {
        client.runsResult = .success(
            HermesJobRunsResponse(hermesJobID: "morning-brief", runs: [.stub(key: "run-1", status: .ok)])
        )
        let sut = HermesMirrorJobDetailViewModel(client: client, job: .stub(id: "morning-brief"))
        await sut.load()

        client.controlResult = .failure(Self.failure(502, "hermes_mirror_upstream_error"))
        await sut.setPaused(true)

        XCTAssertEqual(sut.state, .loaded)
        XCTAssertEqual(sut.runs.count, 1)
        XCTAssertEqual(sut.actionError, .upstream)
    }

    func testPauseAndResumeHitTheirOwnRoutes() async {
        let sut = HermesMirrorJobDetailViewModel(client: client, job: .stub(id: "morning-brief"))

        await sut.setPaused(true)
        await sut.setPaused(false)

        XCTAssertEqual(client.controlCalls, [.pause("morning-brief"), .resume("morning-brief")])
    }

    /// Hermes starts a triggered run asynchronously, so the output is not
    /// back yet; collecting straight after is what makes the new run show up
    /// without waiting for the worker tick.
    func testTriggerCollectsAndRefreshesRatherThanWaitingForTheTick() async {
        client.runsResult = .success(HermesJobRunsResponse(hermesJobID: "morning-brief", runs: []))
        let sut = HermesMirrorJobDetailViewModel(client: client, job: .stub(id: "morning-brief"))

        await sut.trigger()

        XCTAssertEqual(client.controlCalls, [.trigger("morning-brief")])
        XCTAssertEqual(client.collectCalls, ["morning-brief"])
        XCTAssertEqual(client.runsCalls.count, 1)
    }

    func testTriggerDoesNotCollectWhenHermesRefusedTheRun() async {
        client.controlResult = .failure(Self.failure(502, "hermes_mirror_upstream_error"))
        let sut = HermesMirrorJobDetailViewModel(client: client, job: .stub(id: "morning-brief"))

        await sut.trigger()

        XCTAssertTrue(client.collectCalls.isEmpty)
        XCTAssertEqual(sut.actionError, .upstream)
    }

    func testDeleteMarksTheJobGoneSoTheScreenCanPop() async {
        let sut = HermesMirrorJobDetailViewModel(client: client, job: .stub(id: "morning-brief"))

        await sut.delete()

        XCTAssertEqual(client.deleteCalls, ["morning-brief"])
        XCTAssertTrue(sut.isDeleted)
    }

    func testDeleteFailureLeavesTheJobInPlace() async {
        client.deleteResult = .failure(Self.failure(404, "hermes_mirror_not_found"))
        let sut = HermesMirrorJobDetailViewModel(client: client, job: .stub(id: "morning-brief"))

        await sut.delete()

        XCTAssertFalse(sut.isDeleted)
        XCTAssertEqual(sut.actionError, .notFound)
    }

    // MARK: - Editor

    func testCreateNeedsANameAndASchedule() {
        let sut = HermesMirrorJobEditorViewModel(client: client, mode: .create)
        XCTAssertFalse(sut.canSave)

        sut.name = "morning-brief"
        XCTAssertFalse(sut.canSave)

        sut.schedule = "every 2h"
        XCTAssertTrue(sut.canSave)
    }

    func testCreateSendsTheWholeJob() async {
        let sut = HermesMirrorJobEditorViewModel(client: client, mode: .create)
        sut.name = "  morning-brief "
        sut.schedule = "every 2h"
        sut.prompt = "Summarise overnight mail"
        sut.deliver = "origin"
        sut.skills = "research, summarise ,"

        await sut.save()

        let sent = client.createCalls.first
        XCTAssertEqual(sent?.name, "morning-brief")
        XCTAssertEqual(sent?.schedule, "every 2h")
        XCTAssertEqual(sent?.deliver, "origin")
        XCTAssertEqual(sent?.skills, ["research", "summarise"])
    }

    /// The whole reason the editor tracks the original: an edit that only
    /// changes the schedule must not carry a name, a prompt, or nils for the
    /// eight fields this form does not show.
    func testEditSendsOnlyWhatChanged() {
        let job = HermesMirroredJobDTO.stub(id: "morning-brief", name: "morning-brief", schedule: "every 2h", prompt: "Summarise overnight mail")
        let sut = HermesMirrorJobEditorViewModel(client: client, mode: .edit(job))

        sut.schedule = "every 4h"

        let update = sut.updateRequest()
        XCTAssertEqual(update.schedule, "every 4h")
        XCTAssertNil(update.name)
        XCTAssertNil(update.prompt)
        XCTAssertNil(update.skills)
        XCTAssertNil(update.deliver)
        XCTAssertNil(update.model)
        XCTAssertNil(update.enabledToolsets)
    }

    func testEditWithNothingChangedCannotBeSaved() {
        let job = HermesMirroredJobDTO.stub(id: "morning-brief", name: "morning-brief", schedule: "every 2h")
        let sut = HermesMirrorJobEditorViewModel(client: client, mode: .edit(job))

        XCTAssertTrue(sut.updateRequest().isEmpty)
        XCTAssertFalse(sut.canSave)
    }

    /// Blank means "leave it alone", not "clear it" — the list DTO does not
    /// carry `deliver` or `skills`, so the editor cannot prefill them and
    /// must not send an empty value that would wipe them on Hermes.
    func testBlankSkillsAndDeliverAreOmittedRatherThanCleared() {
        let job = HermesMirroredJobDTO.stub(id: "morning-brief", name: "morning-brief", schedule: "every 2h")
        let sut = HermesMirrorJobEditorViewModel(client: client, mode: .edit(job))
        sut.prompt = "New prompt"

        let update = sut.updateRequest()
        XCTAssertEqual(update.prompt, "New prompt")
        XCTAssertNil(update.skills)
        XCTAssertNil(update.deliver)
    }

    func testAScheduleHermesRejectsSurfacesAsABadRequest() async {
        client.createResult = .failure(Self.failure(400, "hermes_mirror_invalid_path"))
        let sut = HermesMirrorJobEditorViewModel(client: client, mode: .create)
        sut.name = "x"
        sut.schedule = "not a schedule"

        await sut.save()

        XCTAssertNil(sut.saved)
        XCTAssertEqual(sut.failure, .badRequest)
    }

    private static func failure(_ status: Int, _ code: String) -> APIError {
        APIError.httpError(statusCode: status, data: Data(#"{"error":{"message":"\#(code)"}}"#.utf8))
    }
}

// MARK: - Stubs

extension HermesMirroredJobDTO {
    static func stub(
        id: String,
        name: String? = nil,
        schedule: String? = "every 2h",
        prompt: String? = nil,
        paused: Bool = false,
        lastRunAt: Date? = nil,
        nextRunAt: Date? = nil
    ) -> HermesMirroredJobDTO {
        HermesMirroredJobDTO(
            hermesJobID: id,
            name: name,
            schedule: schedule,
            prompt: prompt,
            paused: paused,
            lastRunAt: lastRunAt,
            nextRunAt: nextRunAt
        )
    }
}

extension HermesJobRunDTO {
    static func stub(
        key: String,
        status: HermesJobRunStatus,
        output: String? = nil,
        error: String? = nil,
        startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        vaultFilePath: String? = nil,
        tokens: HermesJobRunTokensDTO? = nil
    ) -> HermesJobRunDTO {
        HermesJobRunDTO(
            id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", abs(key.hashValue % 999_999)))")
                ?? UUID(),
            hermesJobID: "morning-brief",
            runKey: key,
            status: status,
            startedAt: startedAt,
            output: output,
            error: error,
            tokens: tokens,
            vaultFilePath: vaultFilePath
        )
    }
}

@MainActor
final class StubHermesMirrorJobsClient: HermesMirrorJobsClientProtocol {
    enum ControlCall: Equatable {
        case pause(String)
        case resume(String)
        case trigger(String)
    }

    var jobsResult: Result<HermesMirroredJobsResponse, any Error> = .success(
        HermesMirroredJobsResponse(source: .live, jobs: [])
    )
    var runsResult: Result<HermesJobRunsResponse, any Error> = .success(
        HermesJobRunsResponse(hermesJobID: "morning-brief", runs: [])
    )
    var controlResult: Result<HermesMirroredJobDTO, any Error> = .success(.stub(id: "morning-brief"))
    var createResult: Result<HermesMirroredJobDTO, any Error> = .success(.stub(id: "morning-brief"))
    var updateResult: Result<HermesMirroredJobDTO, any Error> = .success(.stub(id: "morning-brief"))
    var deleteResult: Result<Void, any Error> = .success(())

    private(set) var controlCalls: [ControlCall] = []
    private(set) var collectCalls: [String] = []
    private(set) var deleteCalls: [String] = []
    private(set) var runsCalls: [String] = []
    private(set) var createCalls: [HermesJobCreateRequest] = []
    private(set) var updateCalls: [(String, HermesJobUpdateRequest)] = []

    nonisolated func jobs() async throws -> HermesMirroredJobsResponse {
        try await MainActor.run { try jobsResult.get() }
    }

    nonisolated func create(_ request: HermesJobCreateRequest) async throws -> HermesMirroredJobDTO {
        try await MainActor.run {
            createCalls.append(request)
            return try createResult.get()
        }
    }

    nonisolated func update(_ jobID: String, _ request: HermesJobUpdateRequest) async throws -> HermesMirroredJobDTO {
        try await MainActor.run {
            updateCalls.append((jobID, request))
            return try updateResult.get()
        }
    }

    nonisolated func pause(_ jobID: String) async throws -> HermesMirroredJobDTO {
        try await MainActor.run {
            controlCalls.append(.pause(jobID))
            return try controlResult.get()
        }
    }

    nonisolated func resume(_ jobID: String) async throws -> HermesMirroredJobDTO {
        try await MainActor.run {
            controlCalls.append(.resume(jobID))
            return try controlResult.get()
        }
    }

    nonisolated func trigger(_ jobID: String) async throws -> HermesMirroredJobDTO {
        try await MainActor.run {
            controlCalls.append(.trigger(jobID))
            return try controlResult.get()
        }
    }

    nonisolated func delete(_ jobID: String) async throws {
        try await MainActor.run {
            deleteCalls.append(jobID)
            try deleteResult.get()
        }
    }

    nonisolated func runs(_ jobID: String, limit _: Int?) async throws -> HermesJobRunsResponse {
        try await MainActor.run {
            runsCalls.append(jobID)
            return try runsResult.get()
        }
    }

    nonisolated func collect(_ jobID: String) async throws -> HermesJobCollectResultDTO {
        await MainActor.run {
            collectCalls.append(jobID)
            return HermesJobCollectResultDTO(
                hermesJobID: jobID,
                fetched: 0,
                inserted: 0,
                skipped: 0,
                filesWritten: 0,
                truncated: false
            )
        }
    }
}
