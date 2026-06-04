// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/BYOHermesOnboardingGate.swift
//
// HER-219 wiring — hosts the optional BYO-Hermes prompt in the post-auth
// onboarding ladder (after ChooseYourBrain, before MainTabView). The
// HER-219 view + view model shipped but were never mounted; this gate is
// the missing coordinator.
//
// Flow:
//   - "Set up now →" presents the live Settings → Hermes Server pane
//     (`HermesGatewayPaneView`) in a sheet so the user can point LuminaVault
//     at their own VPS without leaving onboarding.
//   - "Skip" (or dismissing the setup sheet) calls `onFinished`, which the
//     caller uses to flip the local `hasSeenBYOHermesPrompt` gate so this
//     step never re-presents. There is no server-side latch — the step is
//     idempotent and re-running it is harmless.

import SwiftUI

struct BYOHermesOnboardingGate: View {
    @State private var showSetup = false
    private let settingsClient: any SettingsClientProtocol
    private let onFinished: () -> Void

    init(
        settingsClient: any SettingsClientProtocol,
        onFinished: @escaping () -> Void
    ) {
        self.settingsClient = settingsClient
        self.onFinished = onFinished
    }

    var body: some View {
        BYOHermesPromptView(
            viewModel: BYOHermesPromptViewModel(
                telemetry: LoggerTelemetry(),
                onSetUpNow: { showSetup = true },
                onSkip: onFinished
            )
        )
        .sheet(isPresented: $showSetup) {
            NavigationStack {
                HermesGatewayPaneView(client: settingsClient)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showSetup = false
                                onFinished()
                            }
                        }
                    }
            }
        }
    }
}
