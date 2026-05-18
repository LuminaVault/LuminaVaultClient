// LuminaVaultClient/LuminaVaultClient/App/AppState.swift
import SwiftUI
import Foundation
import PostHog

@Observable
@MainActor
final class AppState {
    var isAuthenticated = false
    var currentUserId: UUID? = nil
    var currentEmail: String? = nil
    /// HER-35: gate flag. False after a fresh signup; flips true after the
    /// user completes the "Create My Vault" screen (or for any user whose
    /// `M37` backfill set them to true).
    var vaultInitialized = false
    let keychain: KeychainService
    let healthKit: HealthKitCoordinator?
    // HER-237: process-wide single-flight refresh coordinator. Every
    // BaseHTTPClient minted via `makeHTTPClient()` shares it so concurrent
    // 401s collapse to one /v1/auth/refresh call.
    private let refreshCoordinator = TokenRefreshCoordinator()

    init(
        keychain: KeychainService = .shared,
        healthKit: HealthKitCoordinator? = nil
    ) {
        self.keychain = keychain
        self.healthKit = healthKit
        self.isAuthenticated = keychain.accessToken != nil
        // Persisted users that re-launched the app have already cleared the
        // vault gate; assume `true` so legacy installs don't get bounced to
        // CreateVaultView. Fresh signups overwrite this in handleAuthSuccess.
        self.vaultInitialized = keychain.accessToken != nil
        if isAuthenticated {
            Task { await healthKit?.start() }
        }
    }

    /// HER-237 — produces a `BaseHTTPClient` wired with token injection,
    /// 401 auto-refresh, and a sign-out trigger when refresh fails. All
    /// per-feature HTTP clients (Vault, Spaces, Memory, Settings, …) MUST
    /// be built through this factory so they share the refresh coordinator.
    func makeHTTPClient() -> BaseHTTPClient {
        let keychain = self.keychain
        let coordinator = self.refreshCoordinator
        // Bootstrap client used solely for `/v1/auth/refresh`. Has no
        // refresh handler of its own, so a 401 on the refresh call itself
        // propagates as `.unauthorized` and the outer client signs the
        // user out.
        let bootstrap = BaseHTTPClient(tokenProvider: { nil })
        let authClient = AuthHTTPClient(client: bootstrap)

        return BaseHTTPClient(
            tokenProvider: { keychain.accessToken },
            refreshHandler: {
                guard let token = keychain.refreshToken else {
                    throw APIError.unauthorized
                }
                let response = try await authClient.refreshToken(token)
                keychain.accessToken = response.accessToken
                keychain.refreshToken = response.refreshToken
                return response.accessToken
            },
            onAuthFailure: { [weak self] in
                await MainActor.run { self?.signOut() }
            },
            refreshCoordinator: coordinator
        )
    }

    func handleAuthSuccess(_ response: AuthResponse) {
        keychain.accessToken = response.accessToken
        keychain.refreshToken = response.refreshToken
        currentUserId = response.userId
        currentEmail = response.email
        vaultInitialized = response.vaultInitialized
        isAuthenticated = true
        Task { await healthKit?.start() }
        // PostHog: identify user so all subsequent events are attributed to them
        // Prefer email if present; otherwise fall back to userId
        let distinctId = response.email ?? response.userId.uuidString
        var userProps: [String: Any] = [:]
        userProps["email"] = response.email
        PostHogSDK.shared.identify(distinctId, userProperties: userProps)
    }

    func signOut() {
        // PostHog: capture sign-out then reset the anonymous distinct ID
        PostHogSDK.shared.capture("user_signed_out")
        PostHogSDK.shared.reset()
        Task { await healthKit?.stop() }
        keychain.clearAll()
        currentUserId = nil
        currentEmail = nil
        vaultInitialized = false
        isAuthenticated = false
    }
}

