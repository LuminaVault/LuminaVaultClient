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
    /// Tracks whether local state has diverged from the last server
    /// snapshot. Save button uses it to enable/disable.
    var hasUnsavedChanges: Bool = false

    private let client: LLMPreferencesClientProtocol
    private var lastServerSnapshot: LLMPreferencesGetResponse?

    init(client: LLMPreferencesClientProtocol) {
        self.client = client
    }

    func load() async {
        state = .loading
        do {
            let response = try await client.get()
            apply(response)
            state = .loaded
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
                body = LLMPreferencesPutRequest(
                    mode: .byok,
                    primaryProvider: primaryProvider,
                    primaryModel: primaryModel,
                    fallbackChain: fallbackChain
                )
            }
            let response = try await client.put(body)
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
        guard let snapshot = lastServerSnapshot else {
            hasUnsavedChanges = true
            return
        }
        hasUnsavedChanges = !(
            snapshot.mode == mode &&
            snapshot.primaryProvider == primaryProvider &&
            snapshot.primaryModel == primaryModel &&
            snapshot.fallbackChain == fallbackChain
        )
    }

    /// HER-300 — `canSave` enables the Save button. Managed mode is
    /// always saveable when dirty (no model field validation needed —
    /// we pin to the canonical default); BYOK additionally requires a
    /// non-empty primary model slug.
    var canSave: Bool {
        guard hasUnsavedChanges else { return false }
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
        lastServerSnapshot = response
        hasUnsavedChanges = false
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
