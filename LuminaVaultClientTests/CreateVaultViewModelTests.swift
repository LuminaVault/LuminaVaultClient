// LuminaVaultClient/LuminaVaultClientTests/CreateVaultViewModelTests.swift
// HER-35 — unit coverage for the vault-gate ViewModel. Asserts that a
// successful create flips AppState.vaultInitialized, and that an error
// surfaces a message without flipping the flag.

@testable import LuminaVaultClient
import Foundation
import XCTest

@MainActor
final class CreateVaultViewModelTests: XCTestCase {
    func testHappyPathFlipsVaultInitialized() async {
        let appState = AppState(keychain: KeychainService(service: "test.create-vault.happy"))
        let mock = MockVaultClient()
        let sut = CreateVaultViewModel(vaultClient: mock, appState: appState)

        await sut.createVault()

        XCTAssertEqual(mock.calls, [.create])
        XCTAssertTrue(appState.vaultInitialized)
        XCTAssertNil(sut.error)
    }

    func testServerErrorSurfacesMessageAndKeepsFlagFalse() async {
        let appState = AppState(keychain: KeychainService(service: "test.create-vault.error"))
        let mock = MockVaultClient()
        mock.createResult = .failure(APIError.httpError(statusCode: 500, data: Data()))
        let sut = CreateVaultViewModel(vaultClient: mock, appState: appState)

        await sut.createVault()

        XCTAssertEqual(mock.calls, [.create])
        XCTAssertFalse(appState.vaultInitialized)
        XCTAssertNotNil(sut.error)
    }

    func testServerReportingUninitializedSurfacesRetryError() async {
        let appState = AppState(keychain: KeychainService(service: "test.create-vault.uninit"))
        let mock = MockVaultClient()
        mock.createResult = .success(VaultStatusResponse(initialized: false))
        let sut = CreateVaultViewModel(vaultClient: mock, appState: appState)

        await sut.createVault()

        XCTAssertFalse(appState.vaultInitialized)
        XCTAssertNotNil(sut.error)
    }
}
