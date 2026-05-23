// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Conversion/ConversionFunnelContainer.swift
//
// HER-287 — root host for the 12-step conversion funnel. Owns the
// `ConversionFunnelState` and switches on its `currentStep` to mount
// the right screen. Shows a progress bar at the top + a back button
// when there's somewhere to go back to.
//
// Completion contract:
//   - When the user reaches `.notificationPrime` and resolves it,
//     `onCompleted` fires.
//   - The caller (LuminaVaultClientApp) sets `hasSeenConversionFunnel`
//     to true AND triggers the paywall via
//     `appState.pendingPaywallID = PaywallPresentation(id: "default")`.
//     HER-211's universal root sheet handles the paywall render.

import SwiftUI

struct ConversionFunnelContainer: View {
    @Environment(\.lvPalette) private var palette
    @State private var state: ConversionFunnelState
    let onCompleted: (ConversionFunnelCompletionSummary) -> Void

    init(
        state: ConversionFunnelState = ConversionFunnelState(),
        onCompleted: @escaping (ConversionFunnelCompletionSummary) -> Void
    ) {
        self._state = State(initialValue: state)
        self.onCompleted = onCompleted
    }

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: state.currentStep)
            }
        }
        .preferredColorScheme(nil)
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 12) {
            HStack {
                backButton
                    .frame(width: 44, height: 32, alignment: .leading)
                Spacer()
                progressBar
                    .frame(maxWidth: 240)
                Spacer()
                Color.clear.frame(width: 44, height: 32)
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 12)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.surface)
                    .frame(height: 4)
                Capsule()
                    .fill(LinearGradient(
                        colors: [palette.accent, palette.primary],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(
                        width: geo.size.width * state.currentStep.progressFraction,
                        height: 4
                    )
                    .animation(.spring(response: 0.4, dampingFraction: 0.85),
                               value: state.currentStep)
            }
        }
        .frame(height: 4)
    }

    @ViewBuilder
    private var backButton: some View {
        if state.currentStep.previous != nil && !state.currentStep.isAutoAdvancing {
            Button {
                state.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Back")
        }
    }

    // MARK: - Step routing

    @ViewBuilder
    private var stepContent: some View {
        switch state.currentStep {
        case .welcome:
            WelcomeFunnelView(state: state)
        case .goal:
            GoalQuestionView(state: state)
        case .painPoints:
            PainPointsView(state: state)
        case .socialProof:
            SocialProofView(state: state)
        case .swipeCards:
            SwipeCardsView(state: state)
        case .personalisedSolution:
            PersonalisedSolutionView(state: state)
        case .comparison:
            ComparisonTableView(state: state)
        case .captureSources:
            CaptureSourcesView(state: state)
        case .processing:
            ProcessingView(state: state)
        case .appDemo:
            AppDemoView(state: state)
        case .valueDelivery:
            ValueDeliveryView(state: state)
        case .notificationPrime:
            NotificationPrimeView(state: state) {
                onCompleted(state.completionSummary())
            }
        }
    }
}

private extension ConversionFunnelStep {
    /// Steps that auto-advance and shouldn't expose a back affordance —
    /// the user can't "go back" into a 2-second animation anyway.
    var isAutoAdvancing: Bool {
        switch self {
        case .processing: return true
        default:          return false
        }
    }
}
