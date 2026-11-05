import Foundation
import Observation

@Observable
@MainActor
final class SelfImprovementViewModel {
    var settings = LVImprovementSettings()
    var status: LVImprovementStatus?
    var runs: [LVImprovementRun] = []
    var changes: [LVImprovementChange] = []
    var resources: [LVImprovementResource] = []
    var isLoading = false
    var isWorking = false
    var errorMessage: String?

    private let client: any SelfImprovementClientProtocol

    init(client: any SelfImprovementClientProtocol) { self.client = client }

    var pendingChanges: [LVImprovementChange] { changes.filter { $0.state == .pending } }
    var canManage: Bool { status?.availability == .managed }

    private enum Loaded: Sendable {
        case status(LVImprovementStatus)
        case runs([LVImprovementRun])
        case changes([LVImprovementChange])
        case resources([LVImprovementResource])
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            var loadedStatus: LVImprovementStatus?
            var loadedRuns: [LVImprovementRun] = []
            var loadedChanges: [LVImprovementChange] = []
            var loadedResources: [LVImprovementResource] = []
            // A task group, not `async let`: see HomeGlanceViewModel.load().
            try await withThrowingTaskGroup(of: Loaded.self) { group in
                group.addTask { .status(try await self.client.status()) }
                group.addTask { .runs(try await self.client.runs()) }
                group.addTask { .changes(try await self.client.changes()) }
                group.addTask { .resources(try await self.client.resources()) }
                for try await item in group {
                    switch item {
                    case .status(let value): loadedStatus = value
                    case .runs(let value): loadedRuns = value
                    case .changes(let value): loadedChanges = value
                    case .resources(let value): loadedResources = value
                    }
                }
            }
            guard let loadedStatus else { return }
            status = loadedStatus
            settings = loadedStatus.settings
            runs = loadedRuns
            changes = loadedChanges
            resources = loadedResources
            errorMessage = nil
        } catch { errorMessage = Self.message(error) }
    }

    func save() async { await work { self.status = try await self.client.update(self.settings) } }

    func runCurator(dryRun: Bool) async {
        await work {
            let run = try await self.client.runCurator(dryRun: dryRun)
            self.runs.insert(run, at: 0)
        }
    }

    func reviewSoul() async {
        await work {
            let run = try await self.client.reviewSoul()
            self.runs.insert(run, at: 0)
        }
    }

    func setPinned(_ resource: LVImprovementResource, pinned: Bool) async {
        await work {
            let updated = try await self.client.pin(resource, pinned: pinned)
            if let index = self.resources.firstIndex(where: { $0.id == updated.id }) {
                self.resources[index] = updated
            }
        }
    }

    func decide(_ change: LVImprovementChange, approve: Bool) async {
        await work {
            let updated = try await self.client.decide(changeID: change.id, approve: approve)
            if let index = self.changes.firstIndex(where: { $0.id == updated.id }) {
                self.changes[index] = updated
            }
        }
    }

    func rollback(_ run: LVImprovementRun) async {
        await work {
            let updated = try await self.client.rollback(runID: run.id)
            if let index = self.runs.firstIndex(where: { $0.id == updated.id }) {
                self.runs[index] = updated
            }
        }
    }

    private func work(_ operation: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do { try await operation(); errorMessage = nil }
        catch { errorMessage = Self.message(error) }
    }

    private static func message(_ error: Error) -> String {
        if case APIError.networkFailure = error { return "Network unavailable." }
        if case APIError.unauthorized = error { return "Session expired — sign in again." }
        return "Self-improvement settings could not be updated."
    }
}
