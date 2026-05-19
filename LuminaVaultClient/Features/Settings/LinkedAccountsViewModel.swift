// LuminaVaultClient/LuminaVaultClient/Features/Settings/LinkedAccountsViewModel.swift
//
// HER-240b — Settings → Linked Accounts state machine.
//
// State machine summary:
//   .loading                       — initial GET in flight
//   .ready(xaiStatus)              — status loaded, can connect / disconnect
//   .failed(message)               — initial load failed (offline / 5xx)
//
// `isWorking` is shared across the disconnect call so the view can disable
// all buttons mid-flight.

import Foundation
import PostHog

@Observable
@MainActor
final class LinkedAccountsViewModel {
    enum State: Equatable, Sendable {
        case loading
        case ready(XaiStatusResponse)
        case failed(message: String)
    }

    var state: State = .loading
    var isWorking: Bool = false
    var disconnectError: String?

    private let client: any IntegrationsClientProtocol

    init(client: any IntegrationsClientProtocol) {
        self.client = client
    }

    /// Initial load. Called on view appear and after a successful connect.
    func load() async {
        state = .loading
        disconnectError = nil
        do {
            let status = try await client.getXaiStatus()
            state = .ready(status)
        } catch {
            state = .failed(message: errorMessage(error))
        }
    }

    /// Called when the connect flow sheet reports a fresh status. Folds it
    /// in without re-fetching.
    func applyConnectResult(_ status: XaiStatusResponse) {
        state = .ready(status)
    }

    func disconnect() async {
        isWorking = true
        disconnectError = nil
        defer { isWorking = false }
        do {
            let status = try await client.disconnectXai()
            state = .ready(status)
            PostHogSDK.shared.capture("xai_disconnected")
        } catch {
            disconnectError = errorMessage(error)
        }
    }

    // MARK: - Convenience for the view

    var xaiStatus: XaiStatusResponse? {
        if case let .ready(status) = state { return status }
        return nil
    }

    private func errorMessage(_ error: Error) -> String {
        if case let APIError.httpError(status, _) = error {
            return "Server returned HTTP \(status)."
        }
        return error.localizedDescription
    }
}
