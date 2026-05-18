// LuminaVaultClient/LuminaVaultClient/Features/Settings/HermesGatewayViewModel.swift
//
// HER-218 — Settings → Advanced → Hermes Gateway state machine.
//
// State machine summary:
//   .loading                       — initial GET in flight
//   .empty                         — server returned 404 (no config)
//   .configured(unverified, …)     — config present, verifiedAt == nil
//   .configured(verified(at:), …)  — config present, verifiedAt != nil
//   .editing                       — form open (new config or update)
//   .testing                       — POST /test in flight
//
// Disconnect, submit, and test-again share `isWorking` so the view can
// disable all buttons during an in-flight network call.

import Foundation
import PostHog

@Observable
@MainActor
final class HermesGatewayViewModel {
    enum VerifyStatus: Equatable, Sendable {
        case unverified
        case verified(at: Date)
    }

    enum State: Equatable, Sendable {
        case loading
        case empty
        case configured(baseUrl: String, hasAuthHeader: Bool, status: VerifyStatus)
        case editing(prefilledBaseUrl: String?, prefilledHasAuthHeader: Bool)
    }

    // MARK: - Observable state
    var state: State = .loading

    // Form fields
    var baseUrlInput: String = ""
    var authHeaderInput: String = ""

    // Banners + per-call status
    var isWorking: Bool = false
    var lastError: String?
    var verifyError: HermesVerifyFailureReason?

    private let client: any SettingsClientProtocol

    init(client: any SettingsClientProtocol) {
        self.client = client
    }

    // MARK: - Actions

    /// Initial load. Called on view appear. Surfaces 404 as `.empty`.
    func load() async {
        state = .loading
        lastError = nil
        verifyError = nil
        do {
            if let config = try await client.getHermesConfig() {
                state = Self.makeConfiguredState(from: config)
            } else {
                state = .empty
            }
        } catch {
            lastError = errorMessage(error)
            // Stay on .loading so the view can show a retry affordance.
        }
    }

    /// Empty-state CTA. Opens the form with no prefill.
    func useMyOwnGateway() {
        baseUrlInput = ""
        authHeaderInput = ""
        state = .editing(prefilledBaseUrl: nil, prefilledHasAuthHeader: false)
        verifyError = nil
    }

    /// Configured-state CTA. Opens the form prefilled with current baseUrl;
    /// auth header field stays blank — server never returns plaintext, the
    /// user must re-paste if they want to rotate.
    func editExistingConfig() {
        if case let .configured(baseUrl, hasAuthHeader, _) = state {
            baseUrlInput = baseUrl
            authHeaderInput = ""
            state = .editing(prefilledBaseUrl: baseUrl, prefilledHasAuthHeader: hasAuthHeader)
            verifyError = nil
        }
    }

    /// Form submit. PUTs the config, then immediately POST-tests it.
    /// On verify failure, leaves the form populated so the user can fix
    /// without re-pasting the auth header.
    func submit() async {
        guard validateBaseUrl(baseUrlInput) else {
            lastError = "Base URL must start with https://"
            return
        }
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        verifyError = nil
        do {
            let trimmedHeader = authHeaderInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let put = try await client.putHermesConfig(
                baseUrl: baseUrlInput,
                authHeader: trimmedHeader.isEmpty ? nil : trimmedHeader,
            )
            do {
                let test = try await client.testHermesConfig()
                let merged = HermesConfigGetResponse(
                    baseUrl: put.baseUrl,
                    hasAuthHeader: put.hasAuthHeader,
                    verifiedAt: test.verifiedAt,
                )
                state = Self.makeConfiguredState(from: merged)
                // PostHog: capture gateway configured and verified
                PostHogSDK.shared.capture("hermes_gateway_configured", properties: [
                    "has_auth_header": put.hasAuthHeader,
                    "verified": true,
                ])
            } catch {
                verifyError = Self.classifyVerifyError(error)
                // Keep the form populated; show config as unverified.
                state = Self.makeConfiguredState(from: put)
                // PostHog: capture gateway configured but unverified
                PostHogSDK.shared.capture("hermes_gateway_configured", properties: [
                    "has_auth_header": put.hasAuthHeader,
                    "verified": false,
                ])
            }
        } catch {
            lastError = errorMessage(error)
        }
    }

    /// Re-run the test against the currently-saved config. Updates
    /// verifiedAt on success or surfaces a banner on failure.
    func testAgain() async {
        guard case let .configured(baseUrl, hasAuthHeader, _) = state else { return }
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        verifyError = nil
        do {
            let test = try await client.testHermesConfig()
            state = .configured(
                baseUrl: baseUrl,
                hasAuthHeader: hasAuthHeader,
                status: .verified(at: test.verifiedAt),
            )
        } catch {
            verifyError = Self.classifyVerifyError(error)
            state = .configured(baseUrl: baseUrl, hasAuthHeader: hasAuthHeader, status: .unverified)
        }
    }

    /// Wipes the config server-side and returns to `.empty`.
    func disconnect() async {
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        verifyError = nil
        do {
            try await client.deleteHermesConfig()
            state = .empty
            // PostHog: capture gateway disconnection
            PostHogSDK.shared.capture("hermes_gateway_disconnected")
        } catch {
            lastError = errorMessage(error)
        }
    }

    /// Closes the form without submitting. Returns to whatever
    /// configured/empty state the server last reported.
    func cancelEditing() async {
        verifyError = nil
        lastError = nil
        await load()
    }

    // MARK: - Helpers

    private func validateBaseUrl(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return false }
        return url.scheme?.lowercased() == "https" && (url.host?.isEmpty == false)
    }

    private static func makeConfiguredState(from config: HermesConfigGetResponse) -> State {
        let status: VerifyStatus = if let v = config.verifiedAt { .verified(at: v) } else { .unverified }
        return .configured(baseUrl: config.baseUrl, hasAuthHeader: config.hasAuthHeader, status: status)
    }

    /// Maps `APIError.httpError` 4xx/5xx into the classified banner the
    /// server documents (`timeout / http_4xx / http_5xx / tls_error`).
    /// Network-layer failures (no response) map to `.timeout` for the UX
    /// copy — the failure mode the user can act on is the same.
    private static func classifyVerifyError(_ error: any Error) -> HermesVerifyFailureReason {
        if let apiError = error as? APIError {
            switch apiError {
            case .httpError(let code, _):
                if (400 ..< 500).contains(code) { return .http4xx }
                if (500 ..< 600).contains(code) { return .http5xx }
                return .unknown
            case .networkFailure:
                return .timeout
            default:
                return .unknown
            }
        }
        return .unknown
    }

    private func errorMessage(_ error: any Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
