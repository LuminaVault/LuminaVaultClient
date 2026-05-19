// LuminaVaultClient/LuminaVaultClient/Features/Settings/GrokConnectFlowViewModel.swift
//
// HER-240b — state machine for the Connect → WKWebView → Complete sheet.

import Foundation
import PostHog

@Observable
@MainActor
final class GrokConnectFlowViewModel {
    enum State: Equatable, Sendable {
        case idle
        case starting
        case awaitingCallback(sessionID: String, authorizeURL: URL)
        case completing
        case success(XaiStatusResponse)
        case failed(message: String)
    }

    var state: State = .idle

    private let client: any IntegrationsClientProtocol

    init(client: any IntegrationsClientProtocol) {
        self.client = client
    }

    /// Entry CTA. POSTs `/start`, transitions to `.awaitingCallback` with
    /// the authorize URL the view embeds in `GrokOAuthWebView`.
    func start() async {
        state = .starting
        do {
            let response = try await client.startXaiConnect()
            guard let url = URL(string: response.authorizeURL) else {
                state = .failed(message: "Server returned an invalid authorize URL.")
                return
            }
            state = .awaitingCallback(sessionID: response.sessionID, authorizeURL: url)
            PostHogSDK.shared.capture("xai_connect_started")
        } catch {
            state = .failed(message: "Couldn't start the xAI Grok connect flow. " + errorMessage(error))
        }
    }

    /// Called by `GrokOAuthWebView` once it intercepts the loopback URL.
    /// Posts the full callback URL to `/complete`; on success transitions
    /// to `.success`, otherwise `.failed`.
    func submitCallback(_ url: URL) async {
        guard case let .awaitingCallback(sessionID, _) = state else { return }
        state = .completing
        do {
            let status = try await client.completeXaiConnect(
                sessionID: sessionID,
                callbackURL: url.absoluteString,
            )
            state = .success(status)
            PostHogSDK.shared.capture("xai_connect_completed", properties: ["tier": status.tier])
        } catch {
            state = .failed(message: "Couldn't complete the xAI Grok connect flow. " + errorMessage(error))
        }
    }

    /// Cancel from inside the webview (user dismisses sheet).
    func cancel() {
        state = .idle
    }

    private func errorMessage(_ error: Error) -> String {
        if case let APIError.httpError(status, _) = error {
            if status == 501 { return "Server hasn't enabled the xAI Grok backend yet." }
            return "Server returned HTTP \(status)."
        }
        return error.localizedDescription
    }
}
