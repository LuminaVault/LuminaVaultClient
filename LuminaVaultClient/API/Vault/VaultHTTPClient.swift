// LuminaVaultClient/LuminaVaultClient/API/Vault/VaultHTTPClient.swift
import Foundation

final class VaultHTTPClient: VaultClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func createVault() async throws -> VaultStatusResponse {
        try await client.execute(VaultEndpoints.Create())
    }

    func status() async throws -> VaultStatusResponse {
        try await client.execute(VaultEndpoints.Status())
    }
}
