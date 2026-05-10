// LuminaVaultClient/LuminaVaultClient/App/AppState.swift
import SwiftUI

@Observable
@MainActor
final class AppState {
    var isAuthenticated = false
    var currentUser: UserDTO? = nil
    let keychain: KeychainService
    let healthKit: HealthKitCoordinator?

    init(
        keychain: KeychainService = .shared,
        healthKit: HealthKitCoordinator? = nil
    ) {
        self.keychain = keychain
        self.healthKit = healthKit
        self.isAuthenticated = keychain.accessToken != nil
        if isAuthenticated {
            // App relaunched with a valid token — restart background sync.
            Task { await healthKit?.start() }
        }
    }

    func handleAuthSuccess(_ response: AuthResponse) {
        keychain.accessToken = response.accessToken
        keychain.refreshToken = response.refreshToken
        currentUser = response.user
        isAuthenticated = true
        Task { await healthKit?.start() }
    }

    func signOut() {
        Task { await healthKit?.stop() }
        keychain.clearAll()
        currentUser = nil
        isAuthenticated = false
    }
}
