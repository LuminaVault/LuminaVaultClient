// LuminaVaultClient/LuminaVaultClientTests/BiometricUnlockTests.swift
//
// HER-103 — cold-launch biometric unlock and Settings toggle coverage.

import XCTest
@testable import LuminaVaultClient

@MainActor
final class BiometricUnlockTests: XCTestCase {
    private var keychains: [KeychainService] = []

    override func tearDown() {
        keychains.forEach { $0.clearAll() }
        keychains.removeAll()
        super.tearDown()
    }

    func testStoredSessionWithoutBiometricPreferenceAuthenticatesOnLaunch() {
        let keychain = makeKeychain()
        keychain.accessToken = "access"
        keychain.refreshToken = "refresh"
        keychain.biometricsEnabled = false

        let state = AppState(keychain: keychain)

        XCTAssertTrue(state.isAuthenticated)
        XCTAssertTrue(state.vaultInitialized)
        XCTAssertFalse(state.needsBiometricUnlock)
    }

    func testStoredSessionWithBiometricPreferenceStartsLocked() {
        let keychain = makeKeychain()
        keychain.accessToken = "access"
        keychain.refreshToken = "refresh"
        keychain.biometricsEnabled = true

        let state = AppState(keychain: keychain)

        XCTAssertFalse(state.isAuthenticated)
        XCTAssertTrue(state.vaultInitialized)
        XCTAssertTrue(state.needsBiometricUnlock)
    }

    func testUnlockStoredSessionRestoresAuthentication() {
        let keychain = makeKeychain()
        keychain.accessToken = "access"
        keychain.refreshToken = "refresh"
        keychain.biometricsEnabled = true
        let state = AppState(keychain: keychain)

        state.unlockStoredSession()

        XCTAssertTrue(state.isAuthenticated)
        XCTAssertTrue(state.vaultInitialized)
        XCTAssertFalse(state.needsBiometricUnlock)
    }

    func testSignOutClearsBiometricPreference() async {
        let keychain = makeKeychain()
        keychain.accessToken = "access"
        keychain.refreshToken = "refresh"
        keychain.biometricsEnabled = true
        let state = AppState(keychain: keychain)

        await state.signOut()

        XCTAssertFalse(keychain.biometricsEnabled)
        XCTAssertNil(keychain.accessToken)
        XCTAssertNil(keychain.refreshToken)
    }

    func testEnablingBiometricUnlockPersistsAfterSuccessfulPrompt() async {
        let keychain = makeKeychain()
        let vm = SecuritySettingsViewModel(
            keychain: keychain,
            biometrics: StubBiometrics(isAvailable: true, result: true)
        )

        await vm.setBiometricUnlockEnabled(true)

        XCTAssertTrue(vm.isBiometricUnlockEnabled)
        XCTAssertTrue(keychain.biometricsEnabled)
        XCTAssertNil(vm.errorMessage)
    }

    func testFailedBiometricEnableLeavesPreferenceOff() async {
        let keychain = makeKeychain()
        let vm = SecuritySettingsViewModel(
            keychain: keychain,
            biometrics: StubBiometrics(isAvailable: true, result: false)
        )

        await vm.setBiometricUnlockEnabled(true)

        XCTAssertFalse(vm.isBiometricUnlockEnabled)
        XCTAssertFalse(keychain.biometricsEnabled)
        XCTAssertNotNil(vm.errorMessage)
    }

    func testUnavailableBiometricsCannotBeEnabled() async {
        let keychain = makeKeychain()
        let vm = SecuritySettingsViewModel(
            keychain: keychain,
            biometrics: StubBiometrics(isAvailable: false, result: true)
        )

        await vm.setBiometricUnlockEnabled(true)

        XCTAssertFalse(vm.isBiometricUnlockEnabled)
        XCTAssertFalse(keychain.biometricsEnabled)
        XCTAssertNotNil(vm.errorMessage)
    }

    func testDisablingBiometricUnlockClearsPreference() async {
        let keychain = makeKeychain()
        keychain.biometricsEnabled = true
        let vm = SecuritySettingsViewModel(
            keychain: keychain,
            biometrics: StubBiometrics(isAvailable: true, result: true)
        )

        await vm.setBiometricUnlockEnabled(false)

        XCTAssertFalse(vm.isBiometricUnlockEnabled)
        XCTAssertFalse(keychain.biometricsEnabled)
    }

    private func makeKeychain() -> KeychainService {
        let keychain = KeychainService(service: "test.her103.\(UUID().uuidString)", inMemory: true)
        keychain.clearAll()
        keychains.append(keychain)
        return keychain
    }
}

private struct StubBiometrics: BiometricsAuthenticating {
    let isAvailable: Bool
    let result: Bool

    func authenticate(reason _: String) async -> Bool {
        result
    }
}
