// LuminaVaultClient/LuminaVaultClient/API/Account/AccountHTTPClient.swift
// HER-212.
import Foundation

final class AccountHTTPClient: AccountClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func deleteAccount() async throws {
        _ = try await client.execute(AccountEndpoints.Delete())
    }
}
