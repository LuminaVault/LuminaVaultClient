// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/ChooseYourBrainScreen.swift
//
// HER-300 ticket 4 — onboarding gate that lets the user pick their LLM
// brain BEFORE landing on the main shell. Two paths:
//
//   • Primary CTA: "Use LuminaVault Default" — keeps the backend-managed
//     funded routing, latches the onboarding step, advances.
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

                LVHaloBackdrop(focalSize: 200, intensity: LVGlow.hero)
                    .allowsHitTesting(false)

                ScrollView {
                    VStack(spacing: LVSpacing.lg) {
                        Image("Lumina/Icons/brain-neural")
                            .resizable()
                            .renderingMode(.original)
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                            .shadow(color: palette.glowPrimary.opacity(0.6), radius: 40, y: 0)
                            .accessibilityHidden(true)
                            .padding(.top, LVSpacing.xl)

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

                            Text("Pick the AI model powering your vault.\nYou can change this anytime in Settings.")
                                .lvFont(.body)
                                .foregroundStyle(palette.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, LVSpacing.base)
                        }

                        VStack(spacing: LVSpacing.md) {
                            primaryCTA
                            secondaryCTA
                        }
                        .padding(.top, LVSpacing.lg)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, LVSpacing.xl)
                    .padding(.bottom, LVSpacing.hero)
                }
                .scrollBounceBehavior(.basedOnSize)
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
        VStack(spacing: LVSpacing.md) {
            VStack(spacing: LVSpacing.xs) {
                Text("Use LuminaVault Default")
                    .lvFont(.subtitle)
                    .foregroundStyle(palette.textPrimary)
                Text("Managed by LuminaVault — no API key needed")
                    .lvFont(.footnote)
                    .foregroundStyle(palette.textSecondary)
            }

            Button {
                Task { await viewModel.acceptManagedDefault() }
            } label: {
                Text("Select Default")
                    .lvFont(.bodyEmphasis)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: LVSize.buttonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: LVRadius.pill, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [palette.primary.opacity(0.8), palette.primary],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSubmitting)
            .opacity(viewModel.isSubmitting ? 0.6 : 1.0)
        }
        .padding(.horizontal, LVSpacing.lg)
        .padding(.vertical, LVSpacing.lg)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: LVGlow.hero)
        .lvInnerGlow(cornerRadius: LVRadius.card, intensity: LVGlow.subtle)
    }

    private var secondaryCTA: some View {
        VStack(spacing: LVSpacing.md) {
            VStack(spacing: LVSpacing.xs) {
                Text("Use my own API key")
                    .lvFont(.subtitle)
                    .foregroundStyle(palette.textPrimary)
                Text("Anthropic, OpenAI, Gemini, Qwen, DeepSeek…")
                    .lvFont(.footnote)
                    .foregroundStyle(palette.textSecondary)
            }

            Button {
                Task { await viewModel.selectBYOK() }
            } label: {
                Text("Enter API Key")
                    .lvFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: LVSize.buttonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: LVRadius.pill, style: .continuous)
                            .fill(palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: LVRadius.pill, style: .continuous)
                            .stroke(palette.surfaceStroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSubmitting)
            .opacity(viewModel.isSubmitting ? 0.6 : 1.0)
        }
        .padding(.horizontal, LVSpacing.lg)
        .padding(.vertical, LVSpacing.lg)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: LVGlow.card)
        .lvInnerGlow(cornerRadius: LVRadius.card, intensity: LVGlow.subtle)
    }
}
