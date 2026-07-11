// LuminaVaultClient/LuminaVaultClient/API/ChatExperience/ChatExperienceEndpoints.swift
//
// Backend contract:
//   GET /v1/chat/inbox
//   GET /v1/me/chat-preferences
//   PUT /v1/me/chat-preferences
import Foundation

enum ChatExperienceEndpoints {
    struct Inbox: Endpoint {
        typealias Response = ChatInboxResponse
        let limit: Int

        var path: String {
            "/v1/chat/inbox?limit=\(limit)"
        }

        var method: HTTPMethod {
            .get
        }
    }

    struct GetPreferences: Endpoint {
        typealias Response = ChatPreferencesGetResponse

        var path: String {
            "/v1/me/chat-preferences"
        }

        var method: HTTPMethod {
            .get
        }
    }

    struct PutPreferences: Endpoint {
        typealias Response = ChatPreferencesGetResponse
        let preferences: ChatPreferencesDTO

        var path: String {
            "/v1/me/chat-preferences"
        }

        var method: HTTPMethod {
            .put
        }

        var body: (any Encodable)? {
            ChatPreferencesPutRequest(preferences: preferences)
        }
    }

    struct GetHybridPreferences: Endpoint {
        typealias Response = HybridRoutingPreferencesDTO
        var path: String {
            "/v1/me/preferences/hybrid-execution"
        }

        var method: HTTPMethod {
            .get
        }
    }

    struct PutHybridPreferences: Endpoint {
        typealias Response = HybridRoutingPreferencesDTO
        let preferences: HybridRoutingPreferencesDTO
        var path: String {
            "/v1/me/preferences/hybrid-execution"
        }

        var method: HTTPMethod {
            .put
        }

        var body: (any Encodable)? {
            preferences
        }
    }
}
