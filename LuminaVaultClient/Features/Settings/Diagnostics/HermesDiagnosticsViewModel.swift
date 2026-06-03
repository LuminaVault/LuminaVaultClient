// LuminaVaultClient/LuminaVaultClient/Features/Settings/Diagnostics/HermesDiagnosticsViewModel.swift
//
// Phase 1 — "is my agent alive + how is it wired" screen. Aggregates
// existing endpoints (LLM preferences, provider credentials, Nous status,
// BYO-Hermes config) into one read-only diagnostics view. No new server
// surface — each source is fetched concurrently and tolerates partial
// failure so one dead endpoint doesn't blank the screen.

import Foundation
import LuminaVaultShared

@MainActor
@Observable
final class HermesDiagnosticsViewModel {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    enum ProbeState: Equatable {
        case idle
        case running
        case ok(Date)
        case failed(String)
    }

    private let llmClient: any LLMPreferencesClientProtocol
    private let providersClient: any ProvidersClientProtocol
    private let integrationsClient: any IntegrationsClientProtocol
    private let settingsClient: any SettingsClientProtocol

    var state: LoadState = .loading

    // Section data — each nil until/unless its fetch succeeds.
    private(set) var preferences: LLMPreferencesGetResponse?
    private(set) var providers: [ProviderCredentialDTO] = []
    private(set) var nous: NousStatusResponse?
    private(set) var hermesConfig: HermesConfigGetResponse?
    private(set) var sectionErrors: [String] = []

    var hermesProbe: ProbeState = .idle

    init(
        llmClient: any LLMPreferencesClientProtocol,
        providersClient: any ProvidersClientProtocol,
        integrationsClient: any IntegrationsClientProtocol,
        settingsClient: any SettingsClientProtocol
    ) {
        self.llmClient = llmClient
        self.providersClient = providersClient
        self.integrationsClient = integrationsClient
        self.settingsClient = settingsClient
    }

    /// Configured providers that hold a credential — what the diagnostics
    /// list should actually show.
    var credentialedProviders: [ProviderCredentialDTO] {
        providers.filter(\.hasCredential)
    }

    func load() async {
        state = .loading
        sectionErrors = []
        hermesProbe = .idle

        // Sequential awaits (not async-let): the clients are main-actor
        // isolated and non-Sendable, so fanning out as child tasks would
        // "send" them across the boundary. They'd serialize on the main actor
        // anyway, so there's no parallelism to lose.
        preferences = await fetch("Model preferences") { try await self.llmClient.get() }
        providers = await fetch("Providers") { try await self.providersClient.list().providers } ?? []
        nous = await fetch("Nous Portal") { try await self.integrationsClient.getNousStatus() }
        // getHermesConfig returns Optional already; unwrap the double-optional.
        hermesConfig = (await fetch("Hermes server") { try await self.settingsClient.getHermesConfig() }) ?? nil

        // Ready as long as at least one source resolved; otherwise the whole
        // screen is dead (likely auth/network) and we surface a hard failure.
        let anyData = preferences != nil || !providers.isEmpty || nous != nil || hermesConfig != nil
        state = anyData || sectionErrors.isEmpty ? .ready : .failed("Couldn't reach your agent.")
    }

    /// On-demand reachability probe. Only meaningful when a BYO-Hermes config
    /// exists; managed-Hermes users have nothing to probe here.
    func probeHermes() async {
        guard hermesConfig != nil else { return }
        hermesProbe = .running
        do {
            let result = try await settingsClient.testHermesConfig()
            hermesProbe = .ok(result.verifiedAt)
        } catch {
            hermesProbe = .failed(error.localizedDescription)
        }
    }

    // MARK: - Internals

    /// Runs a fetch, recording a section error on failure and returning nil so
    /// the rest of the screen still renders.
    private func fetch<T>(_ label: String, _ work: () async throws -> T) async -> T? {
        do {
            return try await work()
        } catch {
            sectionErrors.append("\(label): \(error.localizedDescription)")
            return nil
        }
    }
}

extension ProviderID {
    /// Human-facing provider name for diagnostics rows.
    var diagnosticsLabel: String {
        switch self {
        case .xai: return "xAI (Grok)"
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .ollama: return "Ollama"
        case .openRouter: return "OpenRouter"
        case .nvidia: return "NVIDIA NIM"
        }
    }
}
