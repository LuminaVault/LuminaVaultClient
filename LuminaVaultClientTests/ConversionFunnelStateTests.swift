// LuminaVaultClient/LuminaVaultClientTests/ConversionFunnelStateTests.swift
//
// HER-287 — covers the conversion-funnel state machine: step transitions,
// answer persistence, can-advance gating, demo-pick boundary, swipe-card
// recording.

import XCTest
@testable import LuminaVaultClient

@MainActor
final class ConversionFunnelStateTests: XCTestCase {

    // MARK: - Initial state

    func testInitialStateIsWelcome() {
        let s = ConversionFunnelState()
        XCTAssertEqual(s.currentStep, .welcome)
        XCTAssertNil(s.selectedGoal)
        XCTAssertTrue(s.selectedPains.isEmpty)
        XCTAssertTrue(s.selectedCaptureSources.isEmpty)
        XCTAssertTrue(s.demoPickedCaptureIDs.isEmpty)
    }

    // MARK: - Linear advance

    func testWelcomeAdvancesToGoal() {
        let s = ConversionFunnelState()
        s.advance()
        XCTAssertEqual(s.currentStep, .goal)
    }

    func testGoalGatesUntilSelected() {
        let s = ConversionFunnelState()
        s.advance()  // → goal
        XCTAssertEqual(s.currentStep, .goal)
        XCTAssertFalse(s.canAdvanceFromCurrentStep)
        s.advance()  // no-op
        XCTAssertEqual(s.currentStep, .goal)

        s.selectGoal(.knowledgeBase)
        XCTAssertTrue(s.canAdvanceFromCurrentStep)
        s.advance()
        XCTAssertEqual(s.currentStep, .painPoints)
    }

    // MARK: - Pain points multi-select

    func testTogglePainAddsAndRemoves() {
        let s = ConversionFunnelState()
        s.togglePain(.scatteredNotes)
        XCTAssertTrue(s.selectedPains.contains(.scatteredNotes))
        s.togglePain(.scatteredNotes)
        XCTAssertFalse(s.selectedPains.contains(.scatteredNotes))
    }

    // MARK: - Swipe cards

    func testRecordSwipeAgreedAndDismissedAreExclusive() {
        let s = ConversionFunnelState()
        s.recordSwipe(cardID: 1, agreed: true)
        XCTAssertTrue(s.swipeAgreements.contains(1))
        XCTAssertFalse(s.swipeDismissals.contains(1))

        // User changes their mind — same card, now dismissed.
        s.recordSwipe(cardID: 1, agreed: false)
        XCTAssertFalse(s.swipeAgreements.contains(1))
        XCTAssertTrue(s.swipeDismissals.contains(1))
    }

    // MARK: - Capture sources

    func testToggleCaptureSource() {
        let s = ConversionFunnelState()
        s.toggleCaptureSource(.healthData)
        s.toggleCaptureSource(.voiceMemos)
        XCTAssertEqual(s.selectedCaptureSources, [.healthData, .voiceMemos])
        s.toggleCaptureSource(.healthData)
        XCTAssertEqual(s.selectedCaptureSources, [.voiceMemos])
    }

    // MARK: - Demo picks

    func testDemoPickGatesAdvanceUntilThree() {
        let s = ConversionFunnelState()
        s.currentStep = .appDemo
        XCTAssertFalse(s.canAdvanceFromCurrentStep, "0 picks → can't advance")

        let captures = FunnelSampleCapture.all
        s.recordDemoPick(captureID: captures[0].id)
        XCTAssertFalse(s.canAdvanceFromCurrentStep)
        s.recordDemoPick(captureID: captures[1].id)
        XCTAssertFalse(s.canAdvanceFromCurrentStep)
        s.recordDemoPick(captureID: captures[2].id)
        XCTAssertTrue(s.canAdvanceFromCurrentStep)
    }

    func testDemoPickCapsAtThreeAndRejectsDuplicates() {
        let s = ConversionFunnelState()
        let captures = FunnelSampleCapture.all
        s.recordDemoPick(captureID: captures[0].id)
        s.recordDemoPick(captureID: captures[1].id)
        s.recordDemoPick(captureID: captures[2].id)
        s.recordDemoPick(captureID: captures[3].id)
        XCTAssertEqual(s.demoPickedCaptureIDs.count, 3, "fourth pick is rejected")

        // Duplicate of first
        s.resetDemoPicks()
        s.recordDemoPick(captureID: captures[0].id)
        s.recordDemoPick(captureID: captures[0].id)
        XCTAssertEqual(s.demoPickedCaptureIDs.count, 1, "duplicates rejected")
    }

    // MARK: - Sample capture filtering

    func testFilteredByEmptySetReturnsAll() {
        let filtered = FunnelSampleCapture.filtered(by: [])
        XCTAssertEqual(filtered.count, FunnelSampleCapture.all.count)
    }

    func testFilteredOnlyReturnsMatchingSources() {
        let filtered = FunnelSampleCapture.filtered(by: [.healthData])
        XCTAssertTrue(filtered.allSatisfy { $0.source == .healthData })
        XCTAssertFalse(filtered.isEmpty, "at least one Health sample exists in the seed deck")
    }

    // MARK: - Progress fraction

    func testProgressFractionMonotonicallyIncreases() {
        var last: Double = 0
        for step in ConversionFunnelStep.allCases {
            XCTAssertGreaterThan(step.progressFraction, last)
            last = step.progressFraction
        }
        XCTAssertEqual(ConversionFunnelStep.notificationPrime.progressFraction, 1.0,
            accuracy: 0.001,
            "final step is 100% progress")
    }

    // MARK: - Back navigation

    func testGoBackWalksBackwardsButStopsAtWelcome() {
        let s = ConversionFunnelState()
        s.advance() // → goal
        s.selectGoal(.captureIdeas)
        s.advance() // → painPoints
        XCTAssertEqual(s.currentStep, .painPoints)
        s.goBack()
        XCTAssertEqual(s.currentStep, .goal)
        s.goBack()
        XCTAssertEqual(s.currentStep, .welcome)
        s.goBack()
        XCTAssertEqual(s.currentStep, .welcome, "can't go back past welcome")
    }
}
