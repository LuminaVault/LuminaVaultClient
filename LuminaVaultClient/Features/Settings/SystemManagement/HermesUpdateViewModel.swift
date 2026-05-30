// LuminaVaultClient/LuminaVaultClient/Features/Settings/SystemManagement/HermesUpdateViewModel.swift
//
// HER-330 — drives the "Update Hermes" screen. Holds the version card,
// kicks off the detached server-side update, and observes progress over SSE
// with a status-poll fallback. Reconnects to an in-flight job on appear.

import Foundation
import LuminaVaultShared
import Observation

@Observable
@MainActor
final class HermesUpdateViewModel {
    enum Phase: Equatable {
        case loadingVersion
        case idle
        case updating
        case rollingBack
        case succeeded
        case rolledBack
        case failed
        /// Could not load the version / start the update (e.g. missing admin token).
        case loadError(String)
    }

    private(set) var phase: Phase = .loadingVersion
    private(set) var version: HermesVersionInfo?
    private(set) var job: HermesUpdateJobStatus?
    /// `true` when the server rejected us for auth — surfaces the admin-token field.
    private(set) var needsAdminToken = false

    /// Two-way bound admin-token field. Seeded from the Keychain.
    var adminTokenDraft: String = ""

    @ObservationIgnored private let client: SystemHermesHTTPClient
    @ObservationIgnored private var streamTask: Task<Void, Never>?

    init(client: SystemHermesHTTPClient) {
        self.client = client
        adminTokenDraft = KeychainService.shared.hermesAdminToken ?? ""
    }

    var hasAdminToken: Bool {
        !(KeychainService.shared.hermesAdminToken ?? "").isEmpty
    }

    // MARK: - Lifecycle

    /// Load the version card and re-attach to any in-flight job.
    func load() async {
        phase = .loadingVersion
        needsAdminToken = false
        do {
            // Re-attach first: if an update is running we want the progress UI.
            if let current = try await client.currentJob(), current.state == .running {
                job = current
                phase = .updating
                startStreaming(jobID: current.jobID)
                return
            }
            version = try await client.version()
            phase = .idle
        } catch {
            handleLoadError(error)
        }
    }

    func saveAdminToken() {
        let trimmed = adminTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainService.shared.hermesAdminToken = trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Actions

    func startUpdate() async {
        do {
            let started = try await client.startUpdate(targetTag: nil)
            job = HermesUpdateJobStatus(
                jobID: started.jobID,
                state: .running,
                steps: [],
                fromVersion: version?.currentLabel,
                toVersion: version?.availableLabel,
                startedAt: Date(),
                updatedAt: Date(),
            )
            phase = .updating
            startStreaming(jobID: started.jobID)
        } catch let APIError.httpError(statusCode, _) where statusCode == 409 {
            // Already running elsewhere — re-attach instead of erroring.
            await load()
        } catch {
            handleLoadError(error)
        }
    }

    func rollback() async {
        guard let failedJobID = job?.jobID else { return }
        do {
            let started = try await client.rollback(failedJobID)
            phase = .rollingBack
            job = HermesUpdateJobStatus(
                jobID: started.jobID,
                state: .running,
                steps: [],
                fromVersion: job?.toVersion,
                toVersion: job?.fromVersion,
                startedAt: Date(),
                updatedAt: Date(),
            )
            startStreaming(jobID: started.jobID)
        } catch {
            handleLoadError(error)
        }
    }

    /// Re-load the version card after a terminal state ("Try again" / "Done").
    func reset() async {
        cancelStreaming()
        job = nil
        await load()
    }

    func onDisappear() {
        cancelStreaming()
    }

    // MARK: - Streaming + poll fallback

    private func startStreaming(jobID: UUID) {
        cancelStreaming()
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in client.stream(jobID) {
                    if Task.isCancelled { return }
                    apply(event)
                }
                // Stream ended without a terminal event — reconcile via poll.
                await pollUntilTerminal(jobID: jobID)
            } catch {
                if Task.isCancelled { return }
                // SSE dropped — fall back to polling.
                await pollUntilTerminal(jobID: jobID)
            }
        }
    }

    private func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
    }

    private func apply(_ event: HermesUpdateEvent) {
        switch event {
        case let .step(step):
            mergeStep(step)
        case let .status(state):
            if var snapshot = job {
                snapshot = HermesUpdateJobStatus(
                    jobID: snapshot.jobID,
                    state: state,
                    steps: snapshot.steps,
                    fromVersion: snapshot.fromVersion,
                    toVersion: snapshot.toVersion,
                    errorMessage: snapshot.errorMessage,
                    startedAt: snapshot.startedAt,
                    updatedAt: Date(),
                )
                job = snapshot
            }
        case let .done(snapshot):
            job = snapshot
            applyTerminal(snapshot.state)
        case let .error(message):
            // Stream-level error frame: keep current steps, surface message.
            phase = .failed
            if var snapshot = job {
                snapshot = HermesUpdateJobStatus(
                    jobID: snapshot.jobID,
                    state: .failed,
                    steps: snapshot.steps,
                    fromVersion: snapshot.fromVersion,
                    toVersion: snapshot.toVersion,
                    errorMessage: message,
                    startedAt: snapshot.startedAt,
                    updatedAt: Date(),
                )
                job = snapshot
            }
        }
    }

    private func mergeStep(_ step: HermesUpdateStep) {
        guard var snapshot = job else {
            job = HermesUpdateJobStatus(
                jobID: UUID(),
                state: .running,
                steps: [step],
                startedAt: Date(),
                updatedAt: Date(),
            )
            return
        }
        var steps = snapshot.steps
        if let idx = steps.firstIndex(where: { $0.id == step.id }) {
            steps[idx] = step
        } else {
            steps.append(step)
        }
        snapshot = HermesUpdateJobStatus(
            jobID: snapshot.jobID,
            state: snapshot.state,
            steps: steps,
            fromVersion: snapshot.fromVersion,
            toVersion: snapshot.toVersion,
            errorMessage: snapshot.errorMessage,
            startedAt: snapshot.startedAt,
            updatedAt: Date(),
        )
        job = snapshot
    }

    private func pollUntilTerminal(jobID: UUID) async {
        while !Task.isCancelled {
            do {
                let snapshot = try await client.jobStatus(jobID)
                job = snapshot
                if snapshot.state != .running {
                    applyTerminal(snapshot.state)
                    return
                }
            } catch {
                // Transient — keep trying until cancelled.
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func applyTerminal(_ state: HermesUpdateJobState) {
        switch state {
        case .succeeded: phase = .succeeded
        case .rolledBack: phase = .rolledBack
        case .failed: phase = .failed
        case .running: break
        }
    }

    // MARK: - Errors

    private func handleLoadError(_ error: any Error) {
        switch error {
        case APIError.unauthorized:
            needsAdminToken = true
            phase = .loadError("You don't have permission to update Hermes on this server. Enter the server admin token below.")
        case let APIError.httpError(statusCode, _) where statusCode == 401:
            needsAdminToken = true
            phase = .loadError("You don't have permission to update Hermes on this server. Enter the server admin token below.")
        case let APIError.httpError(statusCode, _) where statusCode == 404:
            needsAdminToken = true
            phase = .loadError("This server doesn't have updates enabled (no admin token configured).")
        default:
            phase = .loadError("Couldn't reach the server. Check your connection and try again.")
        }
    }
}
