// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/ChooseYourBrainViewModel.swift
//
// HER-300 ticket 4 — view model for the "Choose your Brain" onboarding
// gate. Two paths:
//
//   1. `acceptManagedDefault()` — user keeps the LuminaVault-funded
//      server-selected default. PUTs `mode: .managed` to /v1/me/preferences/llm
//      (so server-side routing short-circuits BYOK credential lookup), then
//      PATCHes `brainConfiguredCompleted: true` to latch the onboarding
//      step. Both calls must succeed; on any failure the latch never flips
//      and the user is re-prompted on next launch.
//
//   2. `selectBYOK()` — user wants their own API keys. We PATCH the
//      onboarding latch immediately (the user has DECIDED on BYOK, even if
//      no key has been entered yet — ticket 5 wires the actual key save
//      into the Settings → Intelligence pane), then surface the BYOK
//      navigation via `shouldNavigateToProviders`. The PUT for `mode: .byok`
//      will happen when the user actually saves their first key in
//      ProvidersPaneView; until then the server-side default
//      `mode: .managed` continues to route traffic.
//
// PATCHing on selection (not on first key save) is deliberate: the brain
// step is about CHOICE, not configuration. Treating it as configuration
// would block onboarding until the user has a key, which defeats the
// purpose of having a brain step in the first place.

import Foundation
import LuminaVaultShared

@Observable
@MainActor
final class ChooseYourBrainViewModel {
    private let preferencesClient: any LLMPreferencesClientProtocol
    private let onboardingClient: any OnboardingClientProtocol
    private let onCompleted: @MainActor () -> Void

    /// `true` while either CTA's network calls are in flight. Both buttons
    /// must disable together so a double-tap can't kick off a stray PUT
    /// in parallel with the BYOK PATCH.
    private(set) var isSubmitting: Bool = false

    /// Surfaces the last network failure for the alert in the view. The
    /// user can dismiss + retry by tapping the same CTA again.
    var errorMessage: String?

    /// HER-300 — when `selectBYOK()` succeeds we surface this flag so the
    /// view can present `ProvidersPaneView`. Kept as a boolean instead of
    /// a routing closure so the view stays in charge of navigation.
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

    /// User tapped "Use LuminaVault Default". PUTs the managed-mode
    /// preference row, then latches the onboarding step. Both calls must
    /// succeed; partial-success leaves the user at the same screen on
    /// next launch (the onboarding gate re-fires until the PATCH lands).
    func acceptManagedDefault() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            _ = try await preferencesClient.put(
                // Provider/model are inert compatibility values for the v1
                // schema. The backend ignores them in managed mode.
                LLMPreferencesPutRequest(
                    mode: .managed,
                    primaryProvider: .custom,
                    primaryModel: "",
                    fallbackChain: []
                )
            )
            _ = try await onboardingClient.patch(
                OnboardingPatchRequest(brainConfiguredCompleted: true)
            )
            onCompleted()
        } catch {
            errorMessage = "Couldn't save your choice — \(error.localizedDescription). Tap to retry."
        }
    }

    /// User tapped "Use my own API key". Latches the onboarding step (the
    /// brain decision is done) and signals the view to navigate into
    /// ProvidersPaneView. The actual `mode: .byok` preference write
    /// happens when the user saves their first key in Settings; see
    /// ticket 5 for the Settings → Intelligence pane revamp.
    func selectBYOK() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            _ = try await onboardingClient.patch(
                OnboardingPatchRequest(brainConfiguredCompleted: true)
            )
            shouldNavigateToProviders = true
            onCompleted()
        } catch {
            errorMessage = "Couldn't save your choice — \(error.localizedDescription). Tap to retry."
        }
    }
}
