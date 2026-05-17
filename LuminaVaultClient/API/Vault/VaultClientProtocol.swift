// LuminaVaultClient/LuminaVaultClient/API/Vault/VaultClientProtocol.swift
// HER-35: protocol exists so the CreateVaultView ViewModel can be unit-tested
// against a deterministic mock.
import Foundation

protocol VaultClientProtocol {
    func createVault() async throws -> VaultStatusResponse
    func status() async throws -> VaultStatusResponse
}
