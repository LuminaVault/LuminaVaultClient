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

