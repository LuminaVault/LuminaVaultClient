// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Conversion/ConversionFunnelState.swift
//
// HER-287 — @Observable state for the conversion onboarding funnel.
// Holds the current step + every answer the user gives. The container
// view binds against this; individual screens mutate it via typed
// setters so the navigation contract stays narrow.
//
// Resumability: when the app is killed mid-funnel, the next launch
// picks up at `currentStep` (read from UserDefaults via the container's
// @AppStorage gate). Answers themselves are intentionally in-memory
// only — replaying the funnel from any earlier step is cheap, and
// persisting the answer payload would couple this to a schema.

import Foundation
import Observation

@MainActor
@Observable
final class ConversionFunnelState {
    // MARK: - Position

    var currentStep: ConversionFunnelStep = .welcome

    // MARK: - Screen 2: Goal

    var selectedGoal: FunnelGoal?

    // MARK: - Screen 3: Pain points

    var selectedPains: Set<FunnelPainPoint> = []

    // MARK: - Screen 5: Swipe cards

    /// Cards the user swiped right on (agreed with). Order matches
    /// `FunnelSwipeCard.all`.
    var swipeAgreements: Set<Int> = []
    /// Cards the user swiped left on (dismissed). Recorded for symmetry
    /// + future analytics — currently unused by downstream screens.
    var swipeDismissals: Set<Int> = []

    // MARK: - Screen 8: Capture sources

    var selectedCaptureSources: Set<FunnelCaptureSource> = []

    // MARK: - Screen 10: App demo picks

    /// Sample captures the user swiped right on during the demo.
    /// Bounded to 3 by the screen's logic; the type doesn't enforce it
    /// so tests can assert behaviour at the boundary.
    private(set) var demoPickedCaptureIDs: [UUID] = []

    // MARK: - Step gating

    /// Returns true when the user has given enough input to advance
    /// from the current step. The container reads this to enable /
    /// disable the primary CTA.
    var canAdvanceFromCurrentStep: Bool {
        switch currentStep {
        case .welcome:              return true
        case .goal:                 return selectedGoal != nil
        case .painPoints:           return true     // skippable
        case .socialProof:          return true
        case .swipeCards:           return true     // auto-advance, never blocked
        case .personalisedSolution: return true
        case .comparison:           return true
        case .captureSources:       return true     // skippable; demo falls back to all sources
        case .processing:           return true     // auto-advance
        case .appDemo:              return demoPickedCaptureIDs.count >= 3
        case .valueDelivery:        return true
        case .notificationPrime:    return true     // both Enable and "Not now" advance
        }
    }

    // MARK: - Navigation

    func advance() {
        guard canAdvanceFromCurrentStep, let next = currentStep.next else { return }
        currentStep = next
    }

    func goBack() {
        guard let previous = currentStep.previous else { return }
        currentStep = previous
    }

    // MARK: - Mutations (called from screen views)

    func selectGoal(_ goal: FunnelGoal) {
        selectedGoal = goal
    }

    func togglePain(_ pain: FunnelPainPoint) {
        if selectedPains.contains(pain) {
            selectedPains.remove(pain)
        } else {
            selectedPains.insert(pain)
        }
    }

    func recordSwipe(cardID: Int, agreed: Bool) {
        if agreed {
            swipeAgreements.insert(cardID)
            swipeDismissals.remove(cardID)
        } else {
            swipeDismissals.insert(cardID)
            swipeAgreements.remove(cardID)
        }
    }

    func toggleCaptureSource(_ source: FunnelCaptureSource) {
        if selectedCaptureSources.contains(source) {
            selectedCaptureSources.remove(source)
        } else {
            selectedCaptureSources.insert(source)
        }
    }

    func recordDemoPick(captureID: UUID) {
        guard demoPickedCaptureIDs.count < 3,
              !demoPickedCaptureIDs.contains(captureID) else { return }
        demoPickedCaptureIDs.append(captureID)
    }

    /// Used by tests + the "back" gesture on the demo screen.
    func resetDemoPicks() {
        demoPickedCaptureIDs.removeAll()
    }
}
