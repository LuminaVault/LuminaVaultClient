// LuminaVaultClient/LuminaVaultClient/API/ChatExperience/ChatExperienceHTTPClient.swift
import Foundation

protocol ChatExperienceClientProtocol: Sendable {
    func inbox(limit: Int) async throws -> ChatInboxResponse
    func getPreferences() async throws -> ChatPreferencesGetResponse
    func putPreferences(_ preferences: ChatPreferencesDTO) async throws -> ChatPreferencesGetResponse
    func getHybridPreferences() async throws -> HybridRoutingPreferencesDTO
    func putHybridPreferences(_ preferences: HybridRoutingPreferencesDTO) async throws -> HybridRoutingPreferencesDTO
}

extension ChatExperienceClientProtocol {
    func getHybridPreferences() async throws -> HybridRoutingPreferencesDTO {
        .init()
    }

    func putHybridPreferences(_ preferences: HybridRoutingPreferencesDTO) async throws -> HybridRoutingPreferencesDTO {
        preferences
    }
}

final class ChatExperienceHTTPClient: ChatExperienceClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) {
        self.client = client
    }

    func inbox(limit: Int = 50) async throws -> ChatInboxResponse {
        try await client.execute(ChatExperienceEndpoints.Inbox(limit: limit))
    }

    func getPreferences() async throws -> ChatPreferencesGetResponse {
        try await client.execute(ChatExperienceEndpoints.GetPreferences())
    }

    func putPreferences(_ preferences: ChatPreferencesDTO) async throws -> ChatPreferencesGetResponse {
        try await client.execute(ChatExperienceEndpoints.PutPreferences(preferences: preferences))
    }

    func getHybridPreferences() async throws -> HybridRoutingPreferencesDTO {
        try await client.execute(ChatExperienceEndpoints.GetHybridPreferences())
    }

    func putHybridPreferences(_ preferences: HybridRoutingPreferencesDTO) async throws -> HybridRoutingPreferencesDTO {
        try await client.execute(ChatExperienceEndpoints.PutHybridPreferences(preferences: preferences))
    }
}
