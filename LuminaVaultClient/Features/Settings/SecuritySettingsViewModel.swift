// LuminaVaultClient/LuminaVaultClient/Features/Settings/SecuritySettingsViewModel.swift
//
// HER-103 — local biometric unlock preference for stored sessions.

import Foundation
import Observation

@Observable
@MainActor
final class SecuritySettingsViewModel {
    private let keychain: KeychainService
    private let biometrics: any BiometricsAuthenticating

    var isBiometricUnlockEnabled: Bool
    var isUpdating = false
    var errorMessage: String?

    init(
        keychain: KeychainService,
        biometrics: any BiometricsAuthenticating = BiometricsService.shared
    ) {
        self.keychain = keychain
        self.biometrics = biometrics
        self.isBiometricUnlockEnabled = keychain.biometricsEnabled
    }

    var isBiometricUnlockAvailable: Bool {
        biometrics.isAvailable
    }

    func setBiometricUnlockEnabled(_ enabled: Bool) async {
        errorMessage = nil

        guard enabled else {
            keychain.biometricsEnabled = false
            isBiometricUnlockEnabled = false
            return
        }

        guard biometrics.isAvailable else {
            keychain.biometricsEnabled = false
            isBiometricUnlockEnabled = false
            errorMessage = "Face ID or Touch ID is not available on this device."
            return
        }

        isUpdating = true
        let authenticated = await biometrics.authenticate(
            reason: "Enable Face ID or Touch ID to unlock LuminaVault"
        )
        isUpdating = false

        keychain.biometricsEnabled = authenticated
        isBiometricUnlockEnabled = authenticated
        if !authenticated {
            errorMessage = "Biometric verification was cancelled or failed."
        }
    }
}
