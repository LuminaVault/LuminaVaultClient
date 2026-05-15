// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/BYOHermesPromptView.swift
//
// HER-219 — optional BYO Hermes prompt presented after signup, before
// first capture. Two-button screen: Skip / Set up now.

import SwiftUI

struct BYOHermesPromptView: View {
    @State private var viewModel: BYOHermesPromptViewModel

    init(viewModel: BYOHermesPromptViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "server.rack")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Advanced (optional)")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Already running your own `hermes-agent` on a VPS? Point LuminaVault at it now and your chat traffic will route through your box.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            VStack(spacing: 12) {
                Button("Set up now →") { viewModel.setUpNowTapped() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button("Skip") { viewModel.skipTapped() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Text("You can set this up later in Settings → Advanced.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear { viewModel.onAppear() }
    }
}

#Preview {
    BYOHermesPromptView(viewModel: BYOHermesPromptViewModel(
        telemetry: NoopTelemetry(),
        onSetUpNow: {},
        onSkip: {},
    ))
}
