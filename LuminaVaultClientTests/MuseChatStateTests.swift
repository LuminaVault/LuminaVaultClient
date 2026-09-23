// LuminaVaultClient/LuminaVaultClientTests/MuseChatStateTests.swift
//
// Muse Stage B — one test per row of the contract's "Avatar states + status
// copy" table (`_reviews/muse-chat-contract.md`), against the pure mapping.
// The wiring from the view model into these inputs is covered in
// `ChatObservationScopeTests`; the tool labels riding the run feed in
// `ChatRunFollowerTests`.

import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

@MainActor
final class MuseChatStateTests: XCTestCase {
    private typealias Inputs = MuseChatState.Inputs

    private func derive(_ inputs: Inputs) -> MuseChatState {
        MuseChatState.derive(inputs)
    }

    private func trailItem(_ event: String, tool: String? = nil, seq: Int = 1) -> HermesRunTrailItem? {
        var fields: [String: AnyJSONValue] = [:]
        if let tool { fields["tool"] = .string(tool) }
        return HermesRunTrailItem(event: .stub(seq: seq, event: event, fields: fields))
    }

    // MARK: - Idle / listening

    func testIdleIsReady() {
        let state = derive(Inputs(phase: .idle))
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(state.status, "Ready")
        XCTAssertEqual(state.mascotState, .idle)
        XCTAssertFalse(state.isWorking)
    }

    func testComposerFocusIsListening() {
        let state = derive(Inputs(phase: .idle, isComposerFocused: true))
        XCTAssertEqual(state, .listening)
        XCTAssertEqual(state.status, "is listening")
        XCTAssertFalse(state.isWorking)
    }

    func testVoiceCaptureIsListeningEvenMidTurn() {
        XCTAssertEqual(derive(Inputs(phase: .streaming, isRecordingVoice: true)), .listening)
        XCTAssertEqual(derive(Inputs(phase: .idle, isRecordingVoice: true)), .listening)
    }

    // MARK: - Working

    func testStartingIsThinking() {
        let state = derive(Inputs(phase: .starting))
        XCTAssertEqual(state.status, "is thinking")
        XCTAssertEqual(state.mascotState, .thinking)
        XCTAssertTrue(state.isWorking)
    }

    func testStreamingBeforeFirstTokenIsThinking() {
        XCTAssertEqual(derive(Inputs(phase: .streaming)), .thinking)
    }

    func testStreamingWithTokensIsWriting() {
        let state = derive(Inputs(phase: .streaming, hasFirstToken: true))
        XCTAssertEqual(state, .writing)
        XCTAssertEqual(state.status, "is writing")
        XCTAssertTrue(state.isWorking)
    }

    func testFocusDoesNotInterruptAWorkingTurn() {
        XCTAssertEqual(derive(Inputs(phase: .streaming, isComposerFocused: true)), .thinking)
        XCTAssertEqual(derive(Inputs(phase: .delegated, isComposerFocused: true)), .delegated)
    }

    // MARK: - Delegated runs

    func testDelegatedWithNothingSpecificIsTheLongWait() {
        let state = derive(Inputs(phase: .delegated, lastTrailItem: trailItem("run.started")))
        XCTAssertEqual(state, .delegated)
        XCTAssertEqual(state.status, "is still working — you can leave")
        XCTAssertEqual(state.mascotState, .thinking)
        XCTAssertTrue(state.isWorking)
    }

    func testRunningToolShowsItsLabel() {
        let state = derive(Inputs(phase: .delegated, lastTrailItem: trailItem("tool.started", tool: "web_search")))
        XCTAssertEqual(state, .tool(label: "searching the web"))
        XCTAssertEqual(state.status, "is searching the web")
        XCTAssertTrue(state.isWorking)
    }

    func testCompletedToolFallsBackToTheLongWait() {
        let state = derive(Inputs(phase: .delegated, lastTrailItem: trailItem("tool.completed", tool: "web_search")))
        XCTAssertEqual(state, .delegated)
    }

    func testCompletedToolWithAnswerArrivingIsWriting() {
        let state = derive(Inputs(
            phase: .delegated,
            hasFirstToken: true,
            lastTrailItem: trailItem("tool.completed", tool: "web_search")
        ))
        XCTAssertEqual(state, .writing)
    }

    func testRunningToolBeatsAnswerAlreadyArriving() {
        let state = derive(Inputs(
            phase: .delegated,
            hasFirstToken: true,
            lastTrailItem: trailItem("tool.started", tool: "terminal")
        ))
        XCTAssertEqual(state, .tool(label: "running code"))
    }

    func testPendingApprovalBeatsEverythingOnARun() {
        let state = derive(Inputs(
            phase: .delegated,
            hasFirstToken: true,
            lastTrailItem: trailItem("approval.request"),
            isAwaitingApproval: true
        ))
        XCTAssertEqual(state, .awaitingApproval)
        XCTAssertEqual(state.status, "is waiting for you")
        XCTAssertTrue(state.isWorking)
    }

    // MARK: - Done / failed

    func testCelebratingAfterCompletion() {
        let state = derive(Inputs(phase: .idle, isCelebrating: true))
        XCTAssertEqual(state, .celebrating)
        XCTAssertEqual(state.mascotState, .happy)
        XCTAssertFalse(state.isWorking)
        XCTAssertEqual(MuseChatState.celebrationDuration, .milliseconds(1200))
    }

    func testCelebrationOnlyAppliesWhenIdle() {
        // A new turn started inside the window: the turn wins.
        XCTAssertEqual(derive(Inputs(phase: .starting, isCelebrating: true)), .thinking)
    }

    func testFailedIsASnag() {
        let state = derive(Inputs(phase: .failed(message: "boom")))
        XCTAssertEqual(state, .failed)
        XCTAssertEqual(state.status, "hit a snag")
        XCTAssertEqual(state.mascotState, .idle)
        XCTAssertFalse(state.isWorking)
    }

    func testTypingARetryAfterAFailureIsListening() {
        XCTAssertEqual(derive(Inputs(phase: .failed(message: "boom"), isComposerFocused: true)), .listening)
    }

    // MARK: - Tool labels

    func testKnownToolsGetVerbPhrases() {
        XCTAssertEqual(MuseToolLabel.phrase(tool: "web_search"), "searching the web")
        XCTAssertEqual(MuseToolLabel.phrase(tool: "web_extract"), "reading a page")
        XCTAssertEqual(MuseToolLabel.phrase(tool: "browser_navigate"), "reading a page")
        XCTAssertEqual(MuseToolLabel.phrase(tool: "search_files"), "searching files")
        XCTAssertEqual(MuseToolLabel.phrase(tool: "read_file"), "reading files")
        XCTAssertEqual(MuseToolLabel.phrase(tool: "patch"), "editing files")
        XCTAssertEqual(MuseToolLabel.phrase(tool: "terminal"), "running code")
        XCTAssertEqual(MuseToolLabel.phrase(tool: "shell"), "running code")
        XCTAssertEqual(MuseToolLabel.phrase(tool: "vault_query"), "searching your vault")
        XCTAssertEqual(MuseToolLabel.phrase(tool: "memory"), "checking memory")
        XCTAssertEqual(MuseToolLabel.phrase(tool: "location_recent"), "checking your location")
        XCTAssertEqual(MuseToolLabel.phrase(tool: "weather_forecast"), "checking the weather")
        XCTAssertEqual(MuseToolLabel.phrase(tool: "Calendar.Events"), "checking your calendar")
    }

    func testUnknownToolIsHumanized() {
        XCTAssertEqual(MuseToolLabel.phrase(tool: "frobnicate_widget"), "using frobnicate widget")
    }

    func testMissingToolIsGeneric() {
        XCTAssertEqual(MuseToolLabel.phrase(tool: nil), "using a tool")
        XCTAssertEqual(MuseToolLabel.phrase(tool: "  "), "using a tool")
    }

    func testExplicitLabelWinsOverTheTable() {
        XCTAssertEqual(MuseToolLabel.phrase(tool: "web_search", explicitLabel: "reading the forecast"), "reading the forecast")
    }

    func testLabelsAreCappedAt32Characters() {
        let long = MuseToolLabel.phrase(tool: "an_extraordinarily_long_tool_identifier_name")
        XCTAssertLessThanOrEqual(long.count, MuseToolLabel.maxLength)
        XCTAssertTrue(long.hasSuffix("…"))
        let explicit = MuseToolLabel.phrase(tool: nil, explicitLabel: String(repeating: "x", count: 80))
        XCTAssertEqual(explicit.count, MuseToolLabel.maxLength)
    }
}
