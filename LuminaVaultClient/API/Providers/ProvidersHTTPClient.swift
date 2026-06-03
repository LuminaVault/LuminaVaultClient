// LuminaVaultClient/LuminaVaultClient/API/Providers/ProvidersHTTPClient.swift
//
// HER-252 — concrete `ProvidersClientProtocol` backed by `BaseHTTPClient`.

import Foundation
import LuminaVaultShared

final class ProvidersHTTPClient: ProvidersClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func list() async throws -> ProviderCredentialsListResponse {
        try await client.execute(ProvidersEndpoints.List())
    }

    func upsert(_ provider: ProviderID, _ body: ProviderCredentialPutRequest) async throws -> ProviderCredentialDTO {
        try await client.execute(ProvidersEndpoints.Put(provider: provider, request: body))
    }

    func delete(_ provider: ProviderID) async throws {
        _ = try await client.execute(ProvidersEndpoints.Delete(provider: provider))
    }

    func test(_ provider: ProviderID) async throws -> ProviderTestResponse {
        try await client.execute(ProvidersEndpoints.Test(provider: provider))
    }

    func listPool(_ provider: ProviderID) async throws -> ProviderPoolListResponse {
        try await client.execute(ProvidersEndpoints.ListPool(provider: provider))
    }

    func addPool(_ provider: ProviderID, _ body: ProviderPoolAddRequest) async throws -> ProviderPoolKeyDTO {
        try await client.execute(ProvidersEndpoints.AddPool(provider: provider, request: body))
    }

    func deletePool(_ provider: ProviderID, keyID: UUID) async throws {
        _ = try await client.execute(ProvidersEndpoints.DeletePool(provider: provider, keyID: keyID))
    }
}
