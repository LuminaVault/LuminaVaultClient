// LuminaVaultClient/LuminaVaultClient/API/Providers/ProvidersClientProtocol.swift
//
// HER-252 — per-user external LLM provider credential client. Surfaces
// CRUD + /test. The server's GET returns one row per ProviderID even
// when the user has no credential stored; ViewModels treat
// `hasCredential == false` as the "Not configured" state.

import Foundation
import LuminaVaultShared

protocol ProvidersClientProtocol {
    func list() async throws -> ProviderCredentialsListResponse
    func upsert(_ provider: ProviderID, _ body: ProviderCredentialPutRequest) async throws -> ProviderCredentialDTO
    func delete(_ provider: ProviderID) async throws
    func test(_ provider: ProviderID) async throws -> ProviderTestResponse
}
