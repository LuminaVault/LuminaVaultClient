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
}
