// LuminaVaultClient/LuminaVaultClient/App/AppState.swift
import SwiftUI
import Foundation

@Observable
@MainActor
final class AppState {
    var isAuthenticated = false
    var currentUserId: UUID? = nil
    var currentEmail: String? = nil
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
            Task { await healthKit?.start() }
        }
    }

    func handleAuthSuccess(_ response: AuthResponse) {
        keychain.accessToken = response.accessToken
        keychain.refreshToken = response.refreshToken
        currentUserId = response.userId
        currentEmail = response.email
        isAuthenticated = true
        Task { await healthKit?.start() }
    }

    func signOut() {
        Task { await healthKit?.stop() }
        keychain.clearAll()
        currentUserId = nil
        currentEmail = nil
        isAuthenticated = false
    }
}
