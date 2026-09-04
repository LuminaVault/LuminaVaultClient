// LuminaVaultClient/LuminaVaultClient/Features/Hermes/HermesMirrorJobsViewModels.swift
//
// Hermes Companion Phase 2 "Collect" — the cron jobs running on the user's
// own Hermes, and the runs LuminaVault has collected from them.
//
// The split that shapes these view models: run history is served from
// LuminaVault's own rows, so it loads while the user's machine is asleep,
// while every control (pause, trigger, edit, delete) goes through to Hermes
// and fails when it is offline. A screen that blurred the two would show
// history and then mysteriously refuse to do anything with it — so the
// failure of a control is kept separate from the state of the screen.

import Foundation
import LuminaVaultShared

@Observable
@MainActor
final class HermesMirrorJobsListViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(HermesMirrorFailure)
    }

    private(set) var state: LoadState = .loading
    private(set) var jobs: [HermesMirroredJobDTO] = []
    /// `snapshot` means Hermes was unreachable and these rows come from the
    /// last mirror sync. Worth saying out loud — otherwise a paused job that
    /// was resumed on the machine reads as stale-but-authoritative.
    private(set) var source: HermesMirroredJobsSource = .live

    private let client: any HermesMirrorJobsClientProtocol

    init(client: any HermesMirrorJobsClientProtocol) {
        self.client = client
    }

    /// Seeds a loaded list for previews and snapshot tests.
    convenience init(
        client: any HermesMirrorJobsClientProtocol,
        jobs: [HermesMirroredJobDTO],
        source: HermesMirroredJobsSource = .live
    ) {
        self.init(client: client)
        self.jobs = jobs
        self.source = source
        state = .loaded
    }

    var active: [HermesMirroredJobDTO] { jobs.filter { !$0.paused } }
    var paused: [HermesMirroredJobDTO] { jobs.filter(\.paused) }

    func load() async {
        if jobs.isEmpty { state = .loading }
        do {
            let response = try await client.jobs()
            jobs = response.jobs
            source = response.source
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            let failure = HermesMirrorFailure(error)
            if jobs.isEmpty {
                state = .failed(failure)
            } else {
                state = .loaded
            }
        }
    }
}

@Observable
@MainActor
final class HermesMirrorJobDetailViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(HermesMirrorFailure)
    }

    private(set) var state: LoadState = .loading
    private(set) var job: HermesMirroredJobDTO
    private(set) var runs: [HermesJobRunDTO] = []
    /// When the collector last pulled runs for this job.
    private(set) var collectedAt: Date?
    private(set) var isWorking = false
    /// Set once the job is gone from Hermes; the view pops on it.
    private(set) var isDeleted = false
    /// A failed control, kept apart from `state` so it never blanks the run
    /// history the screen has already loaded.
    var actionError: HermesMirrorFailure?

    private let client: any HermesMirrorJobsClientProtocol
    private let runLimit: Int

    init(client: any HermesMirrorJobsClientProtocol, job: HermesMirroredJobDTO, runLimit: Int = 50) {
        self.client = client
        self.job = job
        self.runLimit = runLimit
    }

    /// Seeds a loaded screen for previews and snapshot tests.
    convenience init(
        client: any HermesMirrorJobsClientProtocol,
        job: HermesMirroredJobDTO,
        runs: [HermesJobRunDTO]
    ) {
        self.init(client: client, job: job)
        self.runs = runs
        state = .loaded
    }

    var title: String {
        let name = job.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name?.isEmpty == false ? name : nil) ?? job.hermesJobID
    }

    var latest: HermesJobRunDTO? { runs.first }
    var history: [HermesJobRunDTO] { Array(runs.dropFirst()) }

    func load() async {
        if runs.isEmpty { state = .loading }
        do {
            let response = try await client.runs(job.hermesJobID, limit: runLimit)
            runs = response.runs
            collectedAt = response.collectedAt
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            let failure = HermesMirrorFailure(error)
            if runs.isEmpty {
                state = .failed(failure)
            } else {
                actionError = failure
            }
        }
    }

    func setPaused(_ paused: Bool) async {
        let jobID = job.hermesJobID
        if paused {
            await control { try await self.client.pause(jobID) }
        } else {
            await control { try await self.client.resume(jobID) }
        }
    }

    /// Runs the job now. Hermes starts it asynchronously, so the output is
    /// not back yet — pull the collected rows after, which is also what makes
    /// the new run appear without waiting for the collector tick.
    func trigger() async {
        await control { try await self.client.trigger(self.job.hermesJobID) }
        guard actionError == nil else { return }
        _ = try? await client.collect(job.hermesJobID)
        await refreshRuns()
    }

    func delete() async {
        guard !isWorking else { return }
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do {
            try await client.delete(job.hermesJobID)
            isDeleted = true
        } catch is CancellationError {
            return
        } catch {
            actionError = HermesMirrorFailure(error)
        }
    }

    /// Adopts the job an editor sheet just saved, so the screen behind it
    /// updates without a round trip.
    func adopt(_ updated: HermesMirroredJobDTO) {
        job = updated
    }

    private func control(_ operation: () async throws -> HermesMirroredJobDTO) async {
        guard !isWorking else { return }
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do {
            job = try await operation()
        } catch is CancellationError {
            return
        } catch {
            actionError = HermesMirrorFailure(error)
        }
    }

    private func refreshRuns() async {
        guard let response = try? await client.runs(job.hermesJobID, limit: runLimit) else { return }
        runs = response.runs
        collectedAt = response.collectedAt
    }
}

/// Create or edit one Hermes cron job.
///
/// Only fields the user actually changed are sent on an edit: the server
/// forwards a partial `updates` object to Hermes, and sending the whole form
/// back would overwrite fields this editor does not show (model, provider,
/// toolsets, workdir) with the nils it holds for them.
@Observable
@MainActor
final class HermesMirrorJobEditorViewModel {
    enum Mode: Equatable {
        case create
        case edit(HermesMirroredJobDTO)
    }

    var name: String
    var schedule: String
    var prompt: String
    var deliver: String
    /// Comma-separated in the field; split on save.
    var skills: String

    private(set) var isSaving = false
    private(set) var failure: HermesMirrorFailure?
    private(set) var saved: HermesMirroredJobDTO?

    let mode: Mode
    private let client: any HermesMirrorJobsClientProtocol
    private let original: HermesMirroredJobDTO?

    init(client: any HermesMirrorJobsClientProtocol, mode: Mode) {
        self.client = client
        self.mode = mode
        switch mode {
        case .create:
            original = nil
            name = ""
            schedule = ""
            prompt = ""
            deliver = ""
            skills = ""
        case .edit(let job):
            original = job
            name = job.name ?? ""
            schedule = job.schedule ?? ""
            prompt = job.prompt ?? ""
            // The list DTO does not carry `deliver` or `skills`; leaving them
            // blank means "unchanged" on an edit, which is exactly right.
            deliver = ""
            skills = ""
        }
    }

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var canSave: Bool {
        guard !isSaving else { return false }
        switch mode {
        case .create:
            return !trimmed(name).isEmpty && !trimmed(schedule).isEmpty
        case .edit:
            return !updateRequest().isEmpty
        }
    }

    func save() async {
        guard canSave else { return }
        isSaving = true
        failure = nil
        defer { isSaving = false }
        do {
            switch mode {
            case .create:
                saved = try await client.create(
                    HermesJobCreateRequest(
                        name: trimmed(name),
                        schedule: trimmed(schedule),
                        prompt: optional(prompt),
                        deliver: optional(deliver),
                        skills: skillList()
                    )
                )
            case .edit(let job):
                saved = try await client.update(job.hermesJobID, updateRequest())
            }
        } catch is CancellationError {
            return
        } catch {
            failure = HermesMirrorFailure(error)
        }
    }

    /// Only what changed. `skills` and `deliver` are absent unless typed,
    /// because blank means "leave it alone", not "clear it".
    func updateRequest() -> HermesJobUpdateRequest {
        HermesJobUpdateRequest(
            name: changed(trimmed(name), from: original?.name),
            schedule: changed(trimmed(schedule), from: original?.schedule),
            prompt: changed(prompt, from: original?.prompt),
            deliver: optional(deliver),
            skills: skillList()
        )
    }

    func skillList() -> [String]? {
        let parsed = skills
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parsed.isEmpty ? nil : parsed
    }

    private func changed(_ value: String, from previous: String?) -> String? {
        let current = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let was = (previous ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard current != was, !current.isEmpty else { return nil }
        return current
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func optional(_ value: String) -> String? {
        let trimmedValue = trimmed(value)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
