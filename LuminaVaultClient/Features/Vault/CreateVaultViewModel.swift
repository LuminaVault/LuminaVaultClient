// LuminaVaultClient/LuminaVaultClient/Features/Vault/CreateVaultViewModel.swift
// HER-35: drives the "Create My Vault" screen. Owns a single one-shot call
// to `POST /v1/vault/create`; on success, flips `AppState.vaultInitialized`
// so the root view switcher mounts MainTabView.
import Foundation
import SwiftUI
import PostHog

@Observable
@MainActor
final class CreateVaultViewModel {
    private let vaultClient: VaultClientProtocol
    private let appState: AppState

    var isLoading = false
    var error: String?

    init(vaultClient: VaultClientProtocol, appState: AppState) {
        self.vaultClient = vaultClient
        self.appState = appState
    }

    func createVault() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let status = try await vaultClient.createVault()
            if status.initialized {
                withAnimation(.easeInOut(duration: 0.4)) {
                    appState.vaultInitialized = true
                }
                // PostHog: capture vault creation (top-of-funnel onboarding completion)
                PostHogSDK.shared.capture("vault_created")
            } else {
                error = "Vault did not initialize. Please try again."
            }
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
