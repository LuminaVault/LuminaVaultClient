// LuminaVaultClient/LuminaVaultClient/Features/Settings/HermesGateways/HermesGatewayDetailViewModel.swift
//
// HER-241 — per-gateway detail/edit screen state.
//
// Today Hermes exposes no admin HTTP API for applying gateway config.
// After Save we surface a "Run this on your Hermes host" footer block
// showing the equivalent CLI command. When Hermes ships an admin API,
// this footer disappears and Save becomes the only step.

import Foundation
import LuminaVaultShared

@Observable
@MainActor
final class HermesGatewayDetailViewModel {
    enum LoadingState: Equatable, Sendable {
        case loading
        case ready
        case loadFailed(message: String)
    }

    enum SaveOutcome: Equatable, Sendable {
        case idle
        case saving
        case saved(verifyOk: Bool, errorCode: String?)
        case error(message: String)
    }

    let gatewayID: HermesGatewayID

    var loadingState: LoadingState = .loading
    var entry: HermesGatewayCatalogEntry?
    /// Form values keyed by field key. Secrets always start blank — the
    /// server never echoes them back, so the user must re-paste to rotate.
    var values: [String: String] = [:]
    var save: SaveOutcome = .idle
    var isDeleting: Bool = false

    /// Live state of the "apply to the running container" actuation flow.
    enum ApplyPhase: Equatable, Sendable {
        case idle
        case applying
        case succeeded
        case failed(message: String)
    }

    var applyPhase: ApplyPhase = .idle
    /// Step rows streamed from the apply job, for the progress UI.
    var applySteps: [HermesGatewayApplyStep] = []

    private let client: any HermesGatewaysClientProtocol

    init(gatewayID: HermesGatewayID, client: any HermesGatewaysClientProtocol) {
        self.gatewayID = gatewayID
        self.client = client
    }

    // MARK: - Actions

    func load() async {
        loadingState = .loading
        do {
            let entry = try await client.get(gatewayID)
            self.entry = entry
            // Seed empty inputs for every required field so the form
            // renders deterministically.
            values = Dictionary(uniqueKeysWithValues: entry.requiredFields.map { ($0.key, "") })
            loadingState = .ready
        } catch {
            loadingState = .loadFailed(message: Self.errorMessage(error))
        }
    }

    /// Save the credentials, then apply them to the running Hermes container
    /// (re-seed `.env` + restart) and stream live progress. On success the
    /// gateway's status flips to `verified`.
    func saveAndApply() async {
        guard let entry else { return }
        // Local validation — server enforces the same contract, but
        // failing fast keeps the iOS UX snappy.
        for field in entry.requiredFields where field.isRequired {
            let value = values[field.key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if value.isEmpty {
                save = .error(message: "Missing \(field.label).")
                return
            }
        }

        save = .saving
        applyPhase = .idle
        applySteps = []
        do {
            let body = HermesGatewayPutRequest(config: values)
            self.entry = try await client.upsert(gatewayID, body)
        } catch {
            save = .error(message: Self.errorMessage(error))
            return
        }

        // Credentials saved — now actuate the container with live progress.
        do {
            let started = try await client.startApply()
            applyPhase = .applying
            await runApplyStream(jobID: started.jobID)
        } catch {
            applyPhase = .failed(message: Self.errorMessage(error))
            save = .error(message: Self.errorMessage(error))
        }
    }

    // MARK: - Apply streaming + poll fallback

    private func runApplyStream(jobID: UUID) async {
        do {
            for try await event in client.applyStream(jobID) {
                if Task.isCancelled { return }
                switch event {
                case let .step(step):
                    mergeApplyStep(step)
                case .status:
                    break // wait for the terminal `.done`
                case let .done(snapshot):
                    applySteps = snapshot.steps
                    await finishApply(state: snapshot.state, message: snapshot.errorMessage)
                    return
                case let .error(message):
                    await finishApply(state: .failed, message: message)
                    return
                }
            }
            // Stream ended without a terminal event — reconcile via poll.
            await pollApplyUntilTerminal(jobID: jobID)
        } catch {
            if Task.isCancelled { return }
            // SSE dropped — fall back to polling.
            await pollApplyUntilTerminal(jobID: jobID)
        }
    }

    private func pollApplyUntilTerminal(jobID: UUID) async {
        while !Task.isCancelled {
            if let snapshot = try? await client.applyStatus(jobID) {
                applySteps = snapshot.steps
                if snapshot.state != .running {
                    await finishApply(state: snapshot.state, message: snapshot.errorMessage)
                    return
                }
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func mergeApplyStep(_ step: HermesGatewayApplyStep) {
        if let idx = applySteps.firstIndex(where: { $0.id == step.id }) {
            applySteps[idx] = step
        } else {
            applySteps.append(step)
        }
    }

    private func finishApply(state: HermesGatewayApplyJobState, message: String?) async {
        switch state {
        case .succeeded:
            applyPhase = .succeeded
            // Re-fetch so the status badge + verifiedAt reflect the apply.
            self.entry = (try? await client.get(gatewayID)) ?? entry
            save = .saved(verifyOk: true, errorCode: nil)
        case .failed:
            applyPhase = .failed(message: message ?? "Applying your settings didn't complete.")
            self.entry = (try? await client.get(gatewayID)) ?? entry
            save = .saved(verifyOk: false, errorCode: "apply_failed")
        case .running:
            break
        }
    }

    func disconnect() async {
        guard entry?.hasConfig == true else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await client.delete(gatewayID)
            // Refresh to flip back to the not-configured row.
            await load()
            values = Dictionary(uniqueKeysWithValues: entry?.requiredFields.map { ($0.key, "") } ?? [])
            save = .idle
        } catch {
            save = .error(message: Self.errorMessage(error))
        }
    }

    // MARK: - Footer copy ("run this on your Hermes host")

    /// Until Hermes ships an admin HTTP API, users must run the CLI on
    /// their Hermes host. This string is shown as copy-to-clipboard in
    /// the detail view footer after a successful Save.
    var manualCliCommand: String {
        "hermes gateway setup \(gatewayID.rawValue)"
    }

    // MARK: - Helpers

    private static func errorMessage(_ error: any Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
