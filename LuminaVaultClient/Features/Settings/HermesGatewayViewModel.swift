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

    /// How the user authenticates to their Hermes. All three collapse to a
    /// single `Authorization` header value sent as `authHeader` — the server
    /// stores/forwards it verbatim and is scheme-agnostic.
    enum AuthMode: String, CaseIterable, Sendable {
        case none
        case bearer
        case basic

        var label: String {
            switch self {
            case .none: "None"
            case .bearer: "Bearer token"
            case .basic: "Username & password"
            }
        }
    }

    // MARK: - Observable state
    var state: State = .loading

    // Form fields
    var baseUrlInput: String = ""
    var authMode: AuthMode = .none
    /// Raw value for `.bearer` — the token, with or without a `Bearer ` prefix.
    var authHeaderInput: String = ""
    /// `.basic` credentials. Combined into `Authorization: Basic <base64>` at submit.
    var basicUsernameInput: String = ""
    var basicPasswordInput: String = ""

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
        resetAuthInputs()
        state = .editing(prefilledBaseUrl: nil, prefilledHasAuthHeader: false)
        verifyError = nil
    }

    /// Configured-state CTA. Opens the form prefilled with current baseUrl;
    /// auth header field stays blank — server never returns plaintext, the
    /// user must re-paste if they want to rotate.
    func editExistingConfig() {
        if case let .configured(baseUrl, hasAuthHeader, _) = state {
            baseUrlInput = baseUrl
            // Server never returns the plaintext header, so we can't know which
            // scheme was used. Blank the inputs; the user re-enters to rotate.
            resetAuthInputs()
            state = .editing(prefilledBaseUrl: baseUrl, prefilledHasAuthHeader: hasAuthHeader)
            verifyError = nil
        }
    }

    /// Clears every auth field and resets the picker to `.none`.
    private func resetAuthInputs() {
        authMode = .none
        authHeaderInput = ""
        basicUsernameInput = ""
        basicPasswordInput = ""
    }

    /// Collapses the current `authMode` + inputs into a single `Authorization`
    /// header value, or `nil` for `.none` / empty. Sent verbatim as `authHeader`.
    private func buildAuthHeader() -> String? {
        switch authMode {
        case .none:
            return nil
        case .bearer:
            let token = authHeaderInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return nil }
            // Accept a raw token or a full "Bearer …" value.
            if token.lowercased().hasPrefix("bearer ") { return token }
            return "Bearer \(token)"
        case .basic:
            let user = basicUsernameInput.trimmingCharacters(in: .whitespacesAndNewlines)
            // Password is intentionally NOT trimmed — trailing/leading spaces
            // can be significant in a password.
            let pass = basicPasswordInput
            guard !user.isEmpty || !pass.isEmpty else { return nil }
            let encoded = Data("\(user):\(pass)".utf8).base64EncodedString()
            return "Basic \(encoded)"
        }
    }

    /// Form submit. PUTs the config, then immediately POST-tests it.
    /// On verify failure, leaves the form populated so the user can fix
    /// without re-pasting the auth header.
    func submit() async {
        guard validateBaseUrl(baseUrlInput) else {
            lastError = "Enter a valid http:// or https:// URL with a host."
            return
        }
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        verifyError = nil
        do {
            let put = try await client.putHermesConfig(
                baseUrl: baseUrlInput,
                authHeader: buildAuthHeader(),
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
        let scheme = url.scheme?.lowercased()
        return (scheme == "https" || scheme == "http") && (url.host?.isEmpty == false)
    }

    /// Non-nil when the typed URL uses insecure transport — shown as a
    /// caution banner in the editing form. The server now accepts these
    /// (BYO_HERMES_REQUIRE_HTTPS=false) but they trade away transport
    /// security: `http://` sends the auth header in plaintext, and a bare
    /// IP can't present a valid TLS certificate.
    var transportWarning: String? {
        let trimmed = baseUrlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else {
            return nil
        }
        if url.scheme?.lowercased() == "http" {
            return "No TLS — your auth token and traffic are sent in plaintext over http://. "
                + "Use https:// with a domain whenever possible."
        }
        if Self.isBareIP(host) {
            return "Raw IP address — there's no certificate to validate, so the connection "
                + "can't be authenticated. A domain + HTTPS is safer."
        }
        return nil
    }

    /// Detects a bare IPv4/IPv6 literal host (no domain). IPv6 hosts from
    /// `URL.host` may arrive bracket-stripped; a `:` is a sufficient tell.
    private static func isBareIP(_ host: String) -> Bool {
        if host.contains(":") { return true }
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let n = Int(part) else { return false }
            return (0 ... 255).contains(n)
        }
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
