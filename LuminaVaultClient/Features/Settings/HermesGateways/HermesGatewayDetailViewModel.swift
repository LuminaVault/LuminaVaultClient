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

    func saveAndTest() async {
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
        do {
            let body = HermesGatewayPutRequest(config: values)
            let updated = try await client.upsert(gatewayID, body)
            self.entry = updated

            // Best-effort reachability probe. The /test endpoint returns
            // 200 even on failure (with `ok: false`); never throws on a
            // probe miss.
            do {
                let result = try await client.test(gatewayID)
                save = .saved(verifyOk: result.ok, errorCode: result.errorCode)
                // Re-fetch so we pick up the new verifiedAt timestamp.
                self.entry = try await client.get(gatewayID)
            } catch {
                save = .saved(verifyOk: false, errorCode: "client_error")
            }
        } catch {
            save = .error(message: Self.errorMessage(error))
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
