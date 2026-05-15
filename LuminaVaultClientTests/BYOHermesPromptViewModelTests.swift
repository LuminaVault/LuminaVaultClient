// LuminaVaultClient/LuminaVaultClientTests/BYOHermesPromptViewModelTests.swift
//
// HER-219 — verifies the three telemetry events fire correctly and the
// coordinator callbacks run exactly once per tap.

import XCTest
@testable import LuminaVaultClient

@MainActor
final class BYOHermesPromptViewModelTests: XCTestCase {
    var telemetry: MockTelemetry!
    var setUpNowCount: Int = 0
    var skipCount: Int = 0

    override func setUp() async throws {
        try await super.setUp()
        telemetry = MockTelemetry()
        setUpNowCount = 0
        skipCount = 0
    }

    private func makeSUT() -> BYOHermesPromptViewModel {
        BYOHermesPromptViewModel(
            telemetry: telemetry,
            onSetUpNow: { [self] in setUpNowCount += 1 },
            onSkip: { [self] in skipCount += 1 },
        )
    }

    func testOnAppearFiresShownEventOnce() {
        let sut = makeSUT()
        sut.onAppear()
        XCTAssertEqual(telemetry.eventNames, [BYOHermesPromptViewModel.Event.shown])
        XCTAssertTrue(sut.hasFiredShownEvent)
    }

    func testOnAppearIsIdempotent() {
        let sut = makeSUT()
        sut.onAppear()
        sut.onAppear()
        sut.onAppear()
        XCTAssertEqual(telemetry.eventNames, [BYOHermesPromptViewModel.Event.shown])
    }

    func testSetUpNowFiresEventAndInvokesCallback() {
        let sut = makeSUT()
        sut.setUpNowTapped()
        XCTAssertEqual(telemetry.eventNames, [BYOHermesPromptViewModel.Event.setUpNow])
        XCTAssertEqual(setUpNowCount, 1)
        XCTAssertEqual(skipCount, 0)
    }

    func testSkipFiresEventAndInvokesCallback() {
        let sut = makeSUT()
        sut.skipTapped()
        XCTAssertEqual(telemetry.eventNames, [BYOHermesPromptViewModel.Event.skipped])
        XCTAssertEqual(skipCount, 1)
        XCTAssertEqual(setUpNowCount, 0)
    }

    func testFullJourneyShownThenSetUpNow() {
        let sut = makeSUT()
        sut.onAppear()
        sut.setUpNowTapped()
        XCTAssertEqual(
            telemetry.eventNames,
            [BYOHermesPromptViewModel.Event.shown, BYOHermesPromptViewModel.Event.setUpNow],
        )
        XCTAssertEqual(setUpNowCount, 1)
        XCTAssertEqual(skipCount, 0)
    }

    func testFullJourneyShownThenSkipped() {
        let sut = makeSUT()
        sut.onAppear()
        sut.skipTapped()
        XCTAssertEqual(
            telemetry.eventNames,
            [BYOHermesPromptViewModel.Event.shown, BYOHermesPromptViewModel.Event.skipped],
        )
        XCTAssertEqual(skipCount, 1)
    }

    func testTelemetryEventNamesMatchSpec() {
        // HER-219 acceptance: exact event names referenced by the
        // downstream analytics dashboard.
        XCTAssertEqual(BYOHermesPromptViewModel.Event.shown, "onboarding.byo_hermes.shown")
        XCTAssertEqual(BYOHermesPromptViewModel.Event.setUpNow, "onboarding.byo_hermes.set_up_now")
        XCTAssertEqual(BYOHermesPromptViewModel.Event.skipped, "onboarding.byo_hermes.skipped")
    }
}

@MainActor
final class LoggerTelemetryTests: XCTestCase {
    func testNoopTelemetryDoesNotCrash() {
        let noop = NoopTelemetry()
        noop.track("anything")
        noop.track("with-properties", properties: ["a": "1", "b": "2"])
    }
}
