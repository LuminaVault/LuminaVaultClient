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
