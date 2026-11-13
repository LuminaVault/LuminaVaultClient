// LuminaVaultClient/LuminaVaultClientTests/Chat/VoiceMode/MicHoldTests.swift
//
// The mic button's touch bookkeeping, without a real touch: the tracker is the
// state the gesture callbacks drive, and `MicHoldStart` is the body of the task
// a press spawns.
@testable import LuminaVaultClient
import XCTest

@MainActor
final class MicHoldTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testActivationRightAfterATouchIsSwallowed() {
        var tracker = MicHoldTracker()
        XCTAssertTrue(tracker.pressBegan())
        XCTAssertTrue(tracker.pressEnded(at: t0))
        XCTAssertTrue(tracker.swallowsActivation(at: t0.addingTimeInterval(0.05)))
    }

    func testActivationDuringAHoldIsSwallowed() {
        var tracker = MicHoldTracker()
        _ = tracker.pressBegan()
        XCTAssertTrue(tracker.swallowsActivation(at: t0))
    }

    func testCancelledTouchDoesNotSwallowTheNextAssistiveActivation() {
        var tracker = MicHoldTracker()
        _ = tracker.pressBegan()
        _ = tracker.pressEnded(at: t0) // cancelled by a system alert: no action follows
        XCTAssertFalse(tracker.swallowsActivation(at: t0.addingTimeInterval(5)))
    }

    func testSwallowedActivationIsConsumedOnce() {
        var tracker = MicHoldTracker()
        _ = tracker.pressBegan()
        _ = tracker.pressEnded(at: t0)
        XCTAssertTrue(tracker.swallowsActivation(at: t0.addingTimeInterval(0.05)))
        XCTAssertFalse(tracker.swallowsActivation(at: t0.addingTimeInterval(0.06)))
    }

    func testReleaseBeforeTheStartTaskRunsNeverOpensTheMic() async {
        let recognizer = StubSpeechRecognizer(available: true, authorized: true)
        let voice = VoiceModeController(recognizer: recognizer, synthesizer: StubSpeechSynthesizer())
        var tracker = MicHoldTracker()
        _ = tracker.pressBegan()
        _ = tracker.pressEnded(at: t0)

        await MicHoldStart.run(voice: voice, isHeld: { tracker.isHeld })

        XCTAssertEqual(recognizer.startCalls, 0)
        XCTAssertFalse(voice.isRecording)
    }

    func testReleaseLandingDuringTheStartStopsTheMic() async {
        let recognizer = StubSpeechRecognizer(available: true, authorized: true)
        let voice = VoiceModeController(recognizer: recognizer, synthesizer: StubSpeechSynthesizer())
        var checks = 0
        // Held when the task begins, gone by the time the start has returned.
        await MicHoldStart.run(voice: voice, isHeld: {
            checks += 1
            return checks == 1
        })

        XCTAssertEqual(recognizer.startCalls, 1)
        XCTAssertEqual(recognizer.stopCalls, 1)
    }

    func testHeldPressKeepsRecording() async {
        let recognizer = StubSpeechRecognizer(available: true, authorized: true)
        let voice = VoiceModeController(recognizer: recognizer, synthesizer: StubSpeechSynthesizer())
        await MicHoldStart.run(voice: voice, isHeld: { true })
        XCTAssertTrue(voice.isRecording)
        XCTAssertEqual(recognizer.stopCalls, 0)
    }
}
