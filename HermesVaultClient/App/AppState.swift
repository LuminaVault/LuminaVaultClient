// HermesVaultClient/HermesVaultClient/App/AppState.swift
import SwiftUI

@Observable
final class AppState {
    var isAuthenticated = false
    var currentUser: UserDTO? = nil
    let keychain: KeychainService

    init(keychain: KeychainService = .shared) {
        self.keychain = keychain
        self.isAuthenticated = keychain.accessToken != nil
    }

    func handleAuthSuccess(_ response: AuthResponse) {
        keychain.accessToken = response.accessToken
        keychain.refreshToken = response.refreshToken
        currentUser = response.user
        isAuthenticated = true
    }

    func signOut() {
        keychain.clearAll()
        currentUser = nil
        isAuthenticated = false
    }
}
