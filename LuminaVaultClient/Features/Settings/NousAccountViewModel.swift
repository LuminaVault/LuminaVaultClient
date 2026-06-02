// LuminaVaultClient/LuminaVaultClient/Features/Settings/NousAccountViewModel.swift
//
// Nous Subscription Integration — Settings → Connections → Connect Nous
// Account state machine. Drives the OAuth device-code flow:
//   load        → GET status
//   startConnect → POST /start, get verifyURL + userCode (open browser)
//   completeConnect → POST /complete (server awaits the polling CLI's exit)
//   disconnect  → DELETE
//
// Unlike the xAI/Grok loopback flow there is no callback URL to capture: the
// in-container CLI self-completes once the user approves in their browser.

import Foundation
import PostHog

@Observable
@MainActor
final class NousAccountViewModel {
    enum State: Sendable {
        case loading
        case ready(NousStatusResponse)
        case failed(message: String)
    }

    /// Sub-state for the connect sheet's device-code handshake.
    enum ConnectPhase: Sendable {
        case idle
        case starting
        /// `/start` succeeded; the user is approving in their browser.
        case awaitingApproval(NousStartResponse)
        /// `/complete` in flight, awaiting the in-container CLI's exit.
        case completing
    }

    var state: State = .loading
    var connectPhase: ConnectPhase = .idle
    var isWorking: Bool = false
    var actionError: String?

    private let client: any IntegrationsClientProtocol

    init(client: any IntegrationsClientProtocol) {
        self.client = client
    }

    /// Initial load. Called on view appear.
    func load() async {
        state = .loading
        actionError = nil
        do {
            let status = try await client.getNousStatus()
            state = .ready(status)
        } catch {
            state = .failed(message: errorMessage(error))
        }
    }

    /// Step 1 — request the device verification URL + user-code.
    func startConnect() async {
        actionError = nil
        connectPhase = .starting
        do {
            let start = try await client.startNousConnect()
            connectPhase = .awaitingApproval(start)
        } catch {
            actionError = errorMessage(error)
            connectPhase = .idle
        }
    }

    /// Step 2 — the user approved in their browser. Await completion; the
    /// server blocks until the polling CLI writes the token and exits.
    func completeConnect() async {
        guard case let .awaitingApproval(start) = connectPhase else { return }
        actionError = nil
        connectPhase = .completing
        isWorking = true
        defer { isWorking = false }
        do {
            let status = try await client.completeNousConnect(sessionID: start.sessionID)
            state = .ready(status)
            connectPhase = .idle
            PostHogSDK.shared.capture("nous_connected")
        } catch {
            actionError = errorMessage(error)
            // Drop back to the approval step so the user can retry the
            // approval without restarting the whole flow.
            connectPhase = .awaitingApproval(start)
        }
    }

    /// Abandon an in-flight connect (user dismissed the sheet).
    func cancelConnect() {
        connectPhase = .idle
    }

    func disconnect() async {
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do {
            let status = try await client.disconnectNous()
            state = .ready(status)
            PostHogSDK.shared.capture("nous_disconnected")
        } catch {
            actionError = errorMessage(error)
        }
    }

    // MARK: - Convenience for the view

    var nousStatus: NousStatusResponse? {
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
