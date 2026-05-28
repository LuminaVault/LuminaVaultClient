// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/ChooseYourBrainScreen.swift
//
// HER-300 ticket 4 — onboarding gate that lets the user pick their LLM
// brain BEFORE landing on the main shell. Two paths:
//
//   • Primary CTA: "Use LuminaVault Default" — keeps the managed
//     Qwen2.5-72B routing, latches the onboarding step, advances.
//   • Secondary CTA: "Use my own API key" — latches the onboarding step
//     and pushes the existing ProvidersPaneView so the user can wire up
//     their first key. (Ticket 5 revamps the Settings → Intelligence
//     surface; for now we reuse the live providers pane.)
//
// No skip button — the choice is one tap and skipping would leave the
// brain mode undefined. The view stays in the onboarding ladder until
// the server-side `brainConfiguredCompleted` latch flips, so a network
// failure re-presents the same screen on next launch.

import LuminaVaultShared
import SwiftUI

struct ChooseYourBrainScreen: View {

    @Environment(\.lvPalette) private var palette
    @State private var viewModel: ChooseYourBrainViewModel
    @State private var showError: Bool = false

    /// HER-300 — built lazily so the BYOK path can hand the same factory
    /// down to `ProvidersPaneView` without `AppState` reaching into the
    /// view. Wired by the caller in `LuminaVaultClientApp`.
    private let makeProvidersClient: () -> ProvidersClientProtocol

    init(
        viewModel: ChooseYourBrainViewModel,
        makeProvidersClient: @escaping () -> ProvidersClientProtocol
    ) {
        _viewModel = State(initialValue: viewModel)
        self.makeProvidersClient = makeProvidersClient
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.lvBackground()

                LVHaloBackdrop(focalSize: 220, intensity: LVGlow.hero)
                    .allowsHitTesting(false)

                ScrollView {
                    VStack(spacing: LVSpacing.xl) {
                        Spacer(minLength: LVSpacing.heroTop)

                        LVIconView(.brainPremium, size: 120, tint: palette.accent)
                            .accessibilityHidden(true)
                            .shadow(color: palette.glowPrimary.opacity(0.4), radius: 28, y: 12)

                        VStack(spacing: LVSpacing.sm) {
                            Text("Choose your Brain")
                                .lvFont(.display)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [palette.accent, palette.primary],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .multilineTextAlignment(.center)

                            Text("Pick the AI model powering your vault. You can change this anytime in Settings.")
                                .lvFont(.body)
                                .foregroundStyle(palette.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, LVSpacing.base)
                        }
                        .padding(.horizontal, LVSpacing.lg)
                        .padding(.vertical, LVSpacing.lg)
                        .lvGlassCard(cornerRadius: LVRadius.card, intensity: LVGlow.hero)
                        .lvInnerGlow(cornerRadius: LVRadius.card, intensity: LVGlow.subtle)
                        .padding(.horizontal, LVSpacing.xl)

                        Spacer(minLength: LVSpacing.base)

                        VStack(spacing: LVSpacing.md) {
                            primaryCTA
                            secondaryCTA
                        }
                        .padding(.horizontal, LVSpacing.xl)
                        .padding(.bottom, LVSpacing.xl)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationDestination(isPresented: $viewModel.shouldNavigateToProviders) {
                ProvidersPaneView(client: makeProvidersClient())
            }
            .alert(
                "Something went wrong",
                isPresented: $showError,
                presenting: viewModel.errorMessage
            ) { _ in
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: { message in
                Text(message)
            }
            .onChange(of: viewModel.errorMessage) { _, newValue in
                showError = (newValue != nil)
            }
        }
    }

    private var primaryCTA: some View {
        VStack(spacing: LVSpacing.xs) {
            LVButton("Use LuminaVault Default", isLoading: viewModel.isSubmitting) {
                Task { await viewModel.acceptManagedDefault() }
            }
            Text("Qwen2.5-72B — free, no API key needed")
                .lvFont(.footnote)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var secondaryCTA: some View {
        Button {
            Task { await viewModel.selectBYOK() }
        } label: {
            VStack(spacing: LVSpacing.xs) {
                Text("Use my own API key")
                    .lvFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                Text("Anthropic, OpenAI, Gemini, Qwen, DeepSeek…")
                    .lvFont(.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: LVSize.largeControlHeight)
            .background(
                RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                    .fill(palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                    .stroke(palette.surfaceStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSubmitting)
        .opacity(viewModel.isSubmitting ? 0.6 : 1.0)
    }
}
