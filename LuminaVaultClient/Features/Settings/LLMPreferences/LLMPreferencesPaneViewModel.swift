// LuminaVaultClient/LuminaVaultClient/Features/Settings/LLMPreferences/LLMPreferencesPaneViewModel.swift
//
// HER-252 — primary model + fallback chain editor. Local state mirrors
// the server snapshot until the user taps Save, at which point we PUT
// the whole thing and replace local state with the server's view.
//
// HER-300 ticket 5 — extends the editor with a `mode` field
// (`.managed` vs `.byok`). The view binds a segmented picker to this
// flag; the BYOK editor is rendered disabled when `mode == .managed`
// so users can preview-without-editing.
//
// When the user saves with `mode == .managed`, we pin the PUT body to
// the LuminaVault-funded canonical default (OpenRouter / Qwen2.5-72B,
// matching `ChooseYourBrainViewModel.managedDefault*`) regardless of
// whatever values the disabled BYOK editor is still holding. This
// guarantees the server sees a consistent managed payload even if a
// previous BYOK config is still in memory.

import Foundation
import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class LLMPreferencesPaneViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// HER-300 — canonical managed-mode model. Duplicated from
    /// `ChooseYourBrainViewModel` to keep the Settings feature
    /// independent of the Onboarding feature; both call sites must
    /// stay in lockstep with the server-side default in
    /// `LLMPreferencesController`.
    static let managedDefaultProvider: ProviderID = .openRouter
    static let managedDefaultModel: String = "qwen/qwen-2.5-72b-instruct"

    var state: LoadState = .loading
    /// HER-300 — `.managed` keeps the user on the LuminaVault-funded
    /// default; `.byok` routes traffic through the user's API keys.
    var mode: LLMBrainMode = .managed
    var primaryProvider: ProviderID = .anthropic
    var primaryModel: String = ""
    var fallbackChain: [ModelRouteDTO] = []
    /// Provider routing constraints (BYOK only). Empty allowed = all allowed.
    /// A provider is never in both sets.
    var allowedProviders: Set<ProviderID> = []
    var blockedProviders: Set<ProviderID> = []
    /// BYOK v2 — inline API key entry for the selected primary provider, so
    /// provider + model + key live on one screen. Saved (PUT credential)
    /// alongside the preference on Save; cleared after a successful write so
    /// the field never displays a stored secret.
    var apiKeyInput: String = ""
    /// Tracks whether local state has diverged from the last server
    /// snapshot. Save button uses it to enable/disable.
    var hasUnsavedChanges: Bool = false

    /// Live model lists fetched per provider from
    /// `GET /v1/me/providers/{id}/models`. Takes precedence over the offline
    /// catalog so rotating lists (e.g. Nous free models) stay current.
    var liveModels: [ProviderID: [LLMModelInfo]] = [:]
    /// True while a live model fetch for the current provider is in flight.
    var modelsLoading: Bool = false
    var routerProfiles: [RouterProfileDTO] = []
    var selectedRouterProfileID: UUID?
    var routerDashboard: RouterDashboardResponse?
    var qualityWeight = 50.0
    var costWeight = 25.0
    var softBudgetUSD = 0.0
    var hardBudgetUSD = 0.0
    var routerDirty = false

    private let client: LLMPreferencesClientProtocol
    private let providersClient: ProvidersClientProtocol
    private let routerClient: RouterClientProtocol?
    private var lastServerSnapshot: LLMPreferencesGetResponse?

    init(
        client: LLMPreferencesClientProtocol,
        providersClient: ProvidersClientProtocol,
        routerClient: RouterClientProtocol? = nil
    ) {
        self.client = client
        self.providersClient = providersClient
        self.routerClient = routerClient
    }

    /// Model list for the selected provider: the live fetch when available,
    /// else the curated offline catalog. Empty → the provider (e.g. ollama)
    /// uses a free-text model field instead of a picker.
    var availableModels: [LLMModelInfo] {
        liveModels[primaryProvider] ?? LLMModelCatalog.models(for: primaryProvider)
    }

    /// Fetch the live model list for a provider and merge it over the
    /// catalog. Failures are swallowed — the offline catalog already backs
    /// `availableModels`, so a dead fetch must not break the picker.
    func refreshModels(for provider: ProviderID) async {
        modelsLoading = true
        defer { if provider == primaryProvider { modelsLoading = false } }
        guard let response = try? await providersClient.models(provider),
              !response.models.isEmpty
        else { return }
        liveModels[provider] = response.models
        // If the freshly-loaded list doesn't contain the current model and
        // this is still the active provider, seed a valid default.
        if provider == primaryProvider,
           !response.models.contains(where: { $0.id == primaryModel }) {
            primaryModel = response.models.first?.id ?? primaryModel
        }
    }

    var usesModelCatalog: Bool { !availableModels.isEmpty }

    /// Picker rows: the curated catalog plus the currently-selected model when
    /// it isn't in the catalog (e.g. a previously-saved managed default like
    /// `qwen/...`, or a custom id). Guarantees the Picker selection always has
    /// a matching tag — otherwise SwiftUI warns + behaves undefined.
    var modelPickerOptions: [LLMModelInfo] {
        var options = availableModels
        if !primaryModel.isEmpty, !options.contains(where: { $0.id == primaryModel }) {
            options.insert(LLMModelInfo(id: primaryModel, displayName: primaryModel), at: 0)
        }
        return options
    }

    /// The value the Model `Picker` should bind its `selection` to. SwiftUI
    /// emits "selection is invalid and does not have an associated tag" when
    /// the bound value isn't among the rendered `.tag`s — which happens on the
    /// pre-load empty default and during the multi-property `apply()` update,
    /// where `selection` can be read a frame before `modelPickerOptions`
    /// recomputes. Coercing the getter to an always-present option silences the
    /// warning and keeps the picker deterministic; the real value is still
    /// written through the setter.
    var pickerSelectedModel: String {
        let options = modelPickerOptions
        if options.contains(where: { $0.id == primaryModel }) { return primaryModel }
        return options.first?.id ?? ""
    }

    /// Switch primary provider and seed a sensible default model from the
    /// catalog so the picker is never left on a model the provider can't serve.
    func selectProvider(_ provider: ProviderID) {
        primaryProvider = provider
        let models = LLMModelCatalog.models(for: provider)
        if let first = models.first, !models.contains(where: { $0.id == primaryModel }) {
            primaryModel = first.id
        }
        apiKeyInput = ""
        markDirty()
        let target = provider
        Task { await refreshModels(for: target) }
    }

    func load() async {
        state = .loading
        do {
            let response = try await client.get()
            apply(response)
            state = .loaded
            await loadRouter()
            await refreshModels(for: primaryProvider)
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    func save() async {
        do {
            // HER-300 — managed payloads always carry the canonical
            // OpenRouter/Qwen pair; the BYOK editor may still hold the
            // user's last BYOK config in memory but we deliberately
            // ignore it on the managed path.
            let body: LLMPreferencesPutRequest
            switch mode {
            case .managed:
                body = LLMPreferencesPutRequest(
                    mode: .managed,
                    primaryProvider: Self.managedDefaultProvider,
                    primaryModel: Self.managedDefaultModel,
                    fallbackChain: []
                )
            case .byok:
                // BYOK v2 — persist the inline API key for the selected
                // provider first (if entered) so the credential exists before
                // the preference points routing at it. ollama uses a host URL
                // (baseUrl), every other provider an apiKey.
                let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedKey.isEmpty {
                    let kind = ProvidersPaneViewModel.defaultKind(for: primaryProvider)
                    let credential = ProviderCredentialPutRequest(
                        kind: kind,
                        apiKey: kind == .hostURL ? nil : trimmedKey,
                        baseUrl: kind == .hostURL ? trimmedKey : nil,
                        label: nil,
                    )
                    _ = try await providersClient.upsert(primaryProvider, credential)
                }
                body = LLMPreferencesPutRequest(
                    mode: .byok,
                    primaryProvider: primaryProvider,
                    primaryModel: primaryModel,
                    fallbackChain: fallbackChain,
                    allowedProviders: Array(allowedProviders),
                    blockedProviders: Array(blockedProviders)
                )
            }
            let response = try await client.put(body)
            if routerDirty, let routerClient, let profile = selectedRouterProfile {
                let latency = max(0, 100 - Int(qualityWeight.rounded()) - Int(costWeight.rounded()))
                let request = RouterProfileWriteRequest(
                    name: profile.name,
                    mode: mode,
                    objective: RouterObjectiveWeightsDTO(
                        quality: Int(qualityWeight.rounded()),
                        cost: Int(costWeight.rounded()),
                        latency: latency
                    ),
                    budget: RouterBudgetPolicyDTO(
                        softLimitUsdMicros: softBudgetUSD > 0 ? Int64(softBudgetUSD * 1_000_000) : nil,
                        hardLimitUsdMicros: hardBudgetUSD > 0 ? Int64(hardBudgetUSD * 1_000_000) : nil
                    ),
                    allowedProviders: Array(allowedProviders),
                    blockedProviders: Array(blockedProviders),
                    defaultAction: profile.defaultAction,
                    rules: profile.rules,
                    expectedRevision: profile.revision
                )
                let updated = try await routerClient.updateProfile(id: profile.id, request: request)
                if let index = routerProfiles.firstIndex(where: { $0.id == updated.id }) {
                    routerProfiles[index] = updated
                }
                _ = try await routerClient.bind(scope: .user, scopeID: "me", profileID: profile.id)
                routerDirty = false
            }
            apiKeyInput = ""
            apply(response)
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    func addFallback() {
        fallbackChain.append(ModelRouteDTO(provider: .openRouter, model: ""))
        markDirty()
    }

    func removeFallback(at offsets: IndexSet) {
        fallbackChain.remove(atOffsets: offsets)
        markDirty()
    }

    func moveFallback(from source: IndexSet, to destination: Int) {
        fallbackChain.move(fromOffsets: source, toOffset: destination)
        markDirty()
    }

    func updateFallback(at index: Int, provider: ProviderID? = nil, model: String? = nil) {
        guard fallbackChain.indices.contains(index) else { return }
        let current = fallbackChain[index]
        fallbackChain[index] = ModelRouteDTO(
            provider: provider ?? current.provider,
            model: model ?? current.model,
        )
        markDirty()
    }

    func markDirty() {
        // A pending inline API key is itself an unsaved change.
        if !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasUnsavedChanges = true
            return
        }
        guard let snapshot = lastServerSnapshot else {
            hasUnsavedChanges = true
            return
        }
        hasUnsavedChanges = !(
            snapshot.mode == mode &&
            snapshot.primaryProvider == primaryProvider &&
            snapshot.primaryModel == primaryModel &&
            snapshot.fallbackChain == fallbackChain &&
            Set(snapshot.allowedProviders) == allowedProviders &&
            Set(snapshot.blockedProviders) == blockedProviders
        )
    }

    /// Toggles a provider's allow-list membership (mutually exclusive with
    /// the block-list).
    func toggleAllowed(_ provider: ProviderID) {
        if allowedProviders.contains(provider) {
            allowedProviders.remove(provider)
        } else {
            allowedProviders.insert(provider)
            blockedProviders.remove(provider)
        }
        markDirty()
    }

    /// Toggles a provider's block-list membership (mutually exclusive with
    /// the allow-list).
    func toggleBlocked(_ provider: ProviderID) {
        if blockedProviders.contains(provider) {
            blockedProviders.remove(provider)
        } else {
            blockedProviders.insert(provider)
            allowedProviders.remove(provider)
        }
        markDirty()
    }

    /// HER-300 — `canSave` enables the Save button. Managed mode is
    /// always saveable when dirty (no model field validation needed —
    /// we pin to the canonical default); BYOK additionally requires a
    /// non-empty primary model slug.
    var canSave: Bool {
        guard hasUnsavedChanges || routerDirty else { return false }
        switch mode {
        case .managed:
            return true
        case .byok:
            return !primaryModel.isEmpty
        }
    }

    private func apply(_ response: LLMPreferencesGetResponse) {
        mode = response.mode
        primaryProvider = response.primaryProvider
        primaryModel = response.primaryModel
        fallbackChain = response.fallbackChain
        allowedProviders = Set(response.allowedProviders)
        blockedProviders = Set(response.blockedProviders)
        // Catalog-backed providers should never sit on an empty model (the
        // Picker has no "" tag). Seed the first catalog entry; free-text
        // providers (e.g. ollama) keep whatever the server sent.
        if usesModelCatalog, primaryModel.isEmpty {
            primaryModel = availableModels.first?.id ?? ""
        }
        lastServerSnapshot = response
        hasUnsavedChanges = false
    }

    var selectedRouterProfile: RouterProfileDTO? {
        guard let selectedRouterProfileID else { return nil }
        return routerProfiles.first { $0.id == selectedRouterProfileID }
    }

    var latencyWeight: Int {
        max(0, 100 - Int(qualityWeight.rounded()) - Int(costWeight.rounded()))
    }

    func selectRouterProfile(_ id: UUID) {
        selectedRouterProfileID = id
        applyRouterProfile()
        routerDirty = true
    }

    func updateQualityWeight(_ value: Double) {
        qualityWeight = min(100, max(0, value))
        costWeight = min(costWeight, 100 - qualityWeight)
        routerDirty = true
    }

    func updateCostWeight(_ value: Double) {
        costWeight = min(100 - qualityWeight, max(0, value))
        routerDirty = true
    }

    private func loadRouter() async {
        guard let routerClient else { return }
        do {
            async let profiles = routerClient.profiles()
            async let dashboard = routerClient.dashboard()
            let (profileResponse, dashboardResponse) = try await (profiles, dashboard)
            routerProfiles = profileResponse.profiles
            selectedRouterProfileID = profileResponse.defaultProfileID
            routerDashboard = dashboardResponse
            applyRouterProfile()
        } catch {
            // Legacy Intelligence settings remain usable against older servers.
        }
    }

    private func applyRouterProfile() {
        guard let profile = selectedRouterProfile else { return }
        qualityWeight = Double(profile.objective.quality)
        costWeight = Double(profile.objective.cost)
        softBudgetUSD = Double(profile.budget.softLimitUsdMicros ?? 0) / 1_000_000
        hardBudgetUSD = Double(profile.budget.hardLimitUsdMicros ?? 0) / 1_000_000
        routerDirty = false
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized: return "Session expired — sign in again."
            case .networkFailure: return "Network unavailable."
            default: return "Couldn't load preferences."
            }
        }
        return "Couldn't load preferences."
    }
}
