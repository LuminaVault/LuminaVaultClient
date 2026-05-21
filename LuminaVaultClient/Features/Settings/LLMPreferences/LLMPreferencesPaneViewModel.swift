// LuminaVaultClient/LuminaVaultClient/Features/Settings/LLMPreferences/LLMPreferencesPaneViewModel.swift
//
// HER-252 — primary model + fallback chain editor. Local state mirrors
// the server snapshot until the user taps Save, at which point we PUT
// the whole thing and replace local state with the server's view.

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

    var state: LoadState = .loading
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
            let body = LLMPreferencesPutRequest(
                primaryProvider: primaryProvider,
                primaryModel: primaryModel,
                fallbackChain: fallbackChain,
            )
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
            snapshot.primaryProvider == primaryProvider &&
            snapshot.primaryModel == primaryModel &&
            snapshot.fallbackChain == fallbackChain
        )
    }

    private func apply(_ response: LLMPreferencesGetResponse) {
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
