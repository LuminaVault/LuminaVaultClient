// LuminaVaultClient/LuminaVaultClient/API/LLMPreferences/LLMPreferencesHTTPClient.swift

import Foundation
import LuminaVaultShared

final class LLMPreferencesHTTPClient: LLMPreferencesClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func get() async throws -> LLMPreferencesGetResponse {
        try await client.execute(LLMPreferencesEndpoints.Get())
    }

    func put(_ body: LLMPreferencesPutRequest) async throws -> LLMPreferencesGetResponse {
        try await client.execute(LLMPreferencesEndpoints.Put(request: body))
    }
}

final class RouterHTTPClient: RouterClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func profiles() async throws -> RouterProfilesResponse {
        try await client.execute(RouterEndpoints.Profiles())
    }

    func catalog() async throws -> RouterCatalogResponse {
        try await client.execute(RouterEndpoints.Catalog())
    }

    func dashboard() async throws -> RouterDashboardResponse {
        try await client.execute(RouterEndpoints.Dashboard())
    }

    func updateProfile(id: UUID, request: RouterProfileWriteRequest) async throws -> RouterProfileDTO {
        try await client.execute(RouterEndpoints.UpdateProfile(id: id, request: request))
    }

    func bindings() async throws -> RouterBindingsResponse {
        try await client.execute(RouterEndpoints.Bindings())
    }

    func bind(scope: RouterBindingScope, scopeID: String, profileID: UUID) async throws -> RouterBindingDTO {
        try await client.execute(RouterEndpoints.PutBinding(scope: scope, scopeID: scopeID, profileID: profileID))
    }

    func unbind(scope: RouterBindingScope, scopeID: String) async throws {
        _ = try await client.execute(RouterEndpoints.DeleteBinding(scope: scope, scopeID: scopeID))
    }
}
