// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/ChooseYourBrainViewModel.swift
//
// HER-300 ticket 4 — view model for the "Choose your Brain" onboarding
// gate. Two paths:
//
//   1. `acceptManagedDefault()` — keep LuminaVault-funded managed routing
//      (OpenRouter / server default already wired). Best-effort PUT
//      `mode: .managed` + PATCH latch, then ALWAYS advance into the app.
//      Network blips must not trap the user on this screen.
//
//   2. `selectBYOK()` — user wants their own API keys. Best-effort PATCH
//      of the onboarding latch, then navigate to ProvidersPaneView.
//      `onCompleted` waits until Providers is dismissed so the parent
//      shell does not tear down mid-push. The PUT for `mode: .byok`
//      happens when the user saves their first key.
//
// Network work runs in VM-owned Tasks (not Button `Task { await }`) so
// toggling `isSubmitting` mid-flight cannot cancel the in-flight request.

import Foundation
import LuminaVaultShared

@Observable
@MainActor
final class ChooseYourBrainViewModel {
    private let preferencesClient: any LLMPreferencesClientProtocol
    private let onboardingClient: any OnboardingClientProtocol
    private let onCompleted: @MainActor () -> Void

    /// `true` while either CTA's network calls are in flight. Both buttons
    /// must disable together so a double-tap can't kick off parallel work.
    private(set) var isSubmitting: Bool = false

    /// Surfaces the last hard failure for the alert in the view. Soft
    /// network failures on Select Default never set this — the app still
    /// advances on the existing managed OpenRouter setup.
    var errorMessage: String?

    /// HER-300 — when `selectBYOK()` finishes its attempt we surface this
    /// so the view can present `ProvidersPaneView`.
    var shouldNavigateToProviders: Bool = false

    init(
        preferencesClient: any LLMPreferencesClientProtocol,
        onboardingClient: any OnboardingClientProtocol,
        onCompleted: @escaping @MainActor () -> Void = {}
    ) {
        self.preferencesClient = preferencesClient
        self.onboardingClient = onboardingClient
        self.onCompleted = onCompleted
    }

    /// User tapped "Select Default" — enter the app on managed routing.
    func acceptManagedDefault() {
        guard !isSubmitting else { return }
        Task { await performAcceptManagedDefault() }
    }

    /// User tapped "Enter API Key" — open Providers (latch best-effort).
    func selectBYOK() {
        guard !isSubmitting else { return }
        Task { await performSelectBYOK() }
    }

    /// Called when the user leaves `ProvidersPaneView` after BYOK selection.
    func finishBYOKNavigation() {
        onCompleted()
    }

    func performAcceptManagedDefault() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        // Best-effort: prefer confirming managed mode + server latch, but
        // never block entry. OpenRouter / managed keys are already on the
        // server; the choice here is "keep that path".
        do {
            _ = try await preferencesClient.put(
                LLMPreferencesPutRequest(
                    mode: .managed,
                    primaryProvider: .custom,
                    primaryModel: "",
                    fallbackChain: []
                )
            )
        } catch {
            // Soft-fail — managed default is already the server baseline.
        }

        do {
            _ = try await onboardingClient.patch(
                OnboardingPatchRequest(brainConfiguredCompleted: true)
            )
        } catch {
            // Soft-fail — local AppStorage latch clears the gate anyway.
        }

        onCompleted()
    }

    func performSelectBYOK() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            _ = try await onboardingClient.patch(
                OnboardingPatchRequest(brainConfiguredCompleted: true)
            )
        } catch {
            guard !Self.isBenignCancellation(error) else {
                // Still open Providers — choice was made.
                shouldNavigateToProviders = true
                return
            }
            // Soft-fail PATCH: still open Providers so the user can enter a key.
        }
        shouldNavigateToProviders = true
    }

    private static func isBenignCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if case APIError.networkFailure(let underlying) = error {
            if underlying is CancellationError { return true }
            if let urlError = underlying as? URLError, urlError.code == .cancelled { return true }
        }
        return false
    }
}
