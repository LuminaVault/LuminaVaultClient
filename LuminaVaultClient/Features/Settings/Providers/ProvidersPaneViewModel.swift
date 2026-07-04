// LuminaVaultClient/LuminaVaultClient/Features/Settings/Providers/ProvidersPaneViewModel.swift
//
// HER-252 — Settings → LLM Providers. List rows for every ProviderID
// case; tap drills into ProviderEditSheet. The server's GET always
// returns one row per supported provider, so the view's data shape is
// stable across "no credential" / "configured" / "failure" states.

import Foundation
import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class ProvidersPaneViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    enum TestResult: Equatable {
        case success(model: String?)
        case failure(code: String)
    }

    var state: LoadState = .loading
    /// Server's last-known row per provider. Indexed by provider for O(1)
    /// row updates on optimistic PUT.
    var rows: [ProviderID: ProviderCredentialDTO] = [:]
    /// Transient toast surfaced after a Test Connection round-trip.
    /// Cleared by the view after it renders.
    var lastTestResult: (provider: ProviderID, result: TestResult)?

    private let client: ProvidersClientProtocol

    init(client: ProvidersClientProtocol) {
        self.client = client
    }

    func load() async {
        state = .loading
        do {
            let response = try await client.list()
            rows = Dictionary(uniqueKeysWithValues: response.providers.map { ($0.provider, $0) })
            state = .loaded
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    func save(provider: ProviderID, kind: ProviderCredentialKind, apiKey: String?, baseUrl: String?, label: String?) async -> Bool {
        let body = ProviderCredentialPutRequest(
            kind: kind,
            apiKey: apiKey?.nonEmpty,
            baseUrl: baseUrl?.nonEmpty,
            label: label?.nonEmpty,
        )
        do {
            let updated = try await client.upsert(provider, body)
            rows[provider] = updated
            return true
        } catch {
            state = .failed(Self.message(for: error))
            return false
        }
    }

    func delete(provider: ProviderID) async -> Bool {
        do {
            try await client.delete(provider)
            // Replace with an empty placeholder so the UI immediately
            // reflects "Not configured" without a full reload.
            rows[provider] = ProviderCredentialDTO(
                provider: provider,
                kind: rows[provider]?.kind ?? Self.defaultKind(for: provider),
                hasCredential: false,
            )
            return true
        } catch {
            state = .failed(Self.message(for: error))
            return false
        }
    }

    func test(provider: ProviderID) async {
        do {
            let response = try await client.test(provider)
            lastTestResult = (provider, .success(model: response.model))
            // Refresh the row so verifiedAt is reflected immediately.
            if let existing = rows[provider] {
                rows[provider] = ProviderCredentialDTO(
                    provider: existing.provider,
                    kind: existing.kind,
                    hasCredential: existing.hasCredential,
                    baseUrl: existing.baseUrl,
                    label: existing.label,
                    verifiedAt: response.verifiedAt,
                    lastFailureAt: nil,
                    lastFailureCode: nil,
                )
            }
        } catch let APIError.httpError(_, data) {
            let code = Self.extractErrorCode(from: data) ?? "upstream_error"
            lastTestResult = (provider, .failure(code: code))
            if let existing = rows[provider] {
                rows[provider] = ProviderCredentialDTO(
                    provider: existing.provider,
                    kind: existing.kind,
                    hasCredential: existing.hasCredential,
                    baseUrl: existing.baseUrl,
                    label: existing.label,
                    verifiedAt: existing.verifiedAt,
                    lastFailureAt: Date(),
                    lastFailureCode: code,
                )
            }
        } catch {
            lastTestResult = (provider, .failure(code: "network"))
        }
    }

    static func defaultKind(for provider: ProviderID) -> ProviderCredentialKind {
        switch provider {
        case .xai, .nvidia, .anthropic, .openai, .openRouter, .gemini, .nous: .apiKey
        case .ollama, .custom: .hostURL
        }
    }

    static func displayName(for provider: ProviderID) -> String {
        switch provider {
        case .xai: "Grok (xAI)"
        case .nvidia: "NVIDIA NIM"
        case .anthropic: "Anthropic Claude"
        case .openai: "OpenAI"
        case .openRouter: "OpenRouter"
        case .ollama: "Ollama (self-hosted)"
        case .gemini: "Google Gemini"
        case .nous: "Nous Research"
        case .custom: "Custom (OpenAI-compatible)"
        }
    }

    private static func extractErrorCode(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // Server's ErrorEnvelope shape: { "error": { "message": "..." } }
        if let error = json["error"] as? [String: Any], let msg = error["message"] as? String {
            return msg
        }
        return json["message"] as? String
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized: return "Session expired — sign in again."
            case .networkFailure: return "Network unavailable."
            default: return "Couldn't load providers."
            }
        }
        return "Couldn't load providers."
    }
}

private extension String {
    /// Returns `nil` when the trimmed string is empty so PUT request
    /// bodies don't carry meaningless empty strings.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
