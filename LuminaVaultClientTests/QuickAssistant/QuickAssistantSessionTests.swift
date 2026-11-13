// LuminaVaultClient/LuminaVaultClientTests/QuickAssistant/QuickAssistantSessionTests.swift
//
// One opening of the card: what gets sent, and what closing it must stop. The
// point of most of these is a late event arriving after the card has gone.
@testable import LuminaVaultClient
import LuminaVaultShared
import XCTest

@MainActor
final class QuickAssistantSessionTests: XCTestCase {
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0 ..< 400 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition(), "condition never became true")
    }

    func testTypedSendCarriesTabAndSpaceUnmapped() async {
        let stub = QuickAssistantStubConversations()
        stub.script = [.token("Hi"), .done]
        let space = UUID()
        let session = QuickAssistantFixture.session(conversations: stub, currentTab: "workspaces", activeSpaceID: space)

        session.send("  remind me  ", viaVoice: false)

        await waitUntil { session.model.reply == "Hi" && session.model.phase == .idle }
        XCTAssertEqual(session.prompt, "remind me")
        XCTAssertEqual(stub.requests.first?.content, "remind me")
        XCTAssertEqual(stub.requests.first?.quickAssistant?.currentTab, "workspaces")
        XCTAssertEqual(stub.requests.first?.quickAssistant?.activeSpaceID, space)
    }

    func testEmptyTextSendsNothing() async {
        let stub = QuickAssistantStubConversations()
        let session = QuickAssistantFixture.session(conversations: stub)

        session.send("   \n", viaVoice: false)
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(stub.requests.count, 0)
        XCTAssertNil(session.prompt)
    }

    func testFinalTranscriptSendsAsVoiceAndSpeaksTheReply() async {
        let stub = QuickAssistantStubConversations()
        stub.script = [.token("Done"), .done]
        let recognizer = StubSpeechRecognizer(available: true, authorized: true)
        let speech = StubSpeechSynthesizer()
        let session = QuickAssistantFixture.session(conversations: stub, recognizer: recognizer, synthesizer: speech)

        await session.voice.startRecording()
        recognizer.emit("what's next")
        try? await Task.sleep(for: .milliseconds(20))
        session.voice.stopRecording()
        recognizer.finish()

        await waitUntil { speech.spokenTexts == ["Done"] }
        XCTAssertEqual(stub.requests.first?.content, "what's next")
        XCTAssertEqual(session.prompt, "what's next")
    }

    func testEmptyTranscriptSendsNothingAndShowsTheExistingMessage() async {
        let stub = QuickAssistantStubConversations()
        let recognizer = StubSpeechRecognizer(available: true, authorized: true)
        let session = QuickAssistantFixture.session(conversations: stub, recognizer: recognizer)

        await session.voice.startRecording()
        session.voice.stopRecording()
        recognizer.finish()

        await waitUntil { session.voice.errorMessage != nil }
        XCTAssertEqual(session.voice.errorMessage, "Didn't catch that. Try again.")
        XCTAssertEqual(stub.requests.count, 0)
    }

    func testDeniedPermissionShowsTheExistingMessageAndSendsNothing() async {
        let stub = QuickAssistantStubConversations()
        let recognizer = StubSpeechRecognizer(available: true, authorized: false)
        let session = QuickAssistantFixture.session(conversations: stub, recognizer: recognizer)

        await session.voice.startRecording()

        XCTAssertEqual(
            session.voice.errorMessage,
            "Enable Microphone & Speech Recognition in Settings to talk to Lumina."
        )
        XCTAssertEqual(recognizer.startCalls, 0)
        XCTAssertEqual(stub.requests.count, 0)
    }

    func testClosingWhileRecordingStopsTheMicAndDropsTheTranscript() async {
        let stub = QuickAssistantStubConversations()
        let recognizer = StubSpeechRecognizer(available: true, authorized: true)
        let session = QuickAssistantFixture.session(conversations: stub, recognizer: recognizer)

        await session.voice.startRecording()
        recognizer.emit("half a sentence")
        try? await Task.sleep(for: .milliseconds(20))

        session.close()
        XCTAssertEqual(recognizer.stopCalls, 1)

        // The recognizer still delivers its final result after `stop()`.
        recognizer.finish()
        await waitUntil { session.voice.state == .idle }
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(stub.requests.count, 0)
    }

    func testClosingMidTurnResetsAndClosesTheStream() async {
        let stub = QuickAssistantStubConversations()
        stub.script = [.token("Partial")]
        stub.holdsStream = true
        let session = QuickAssistantFixture.session(conversations: stub)

        session.send("hello", viaVoice: false)
        await waitUntil { session.model.reply == "Partial" }

        session.close()

        XCTAssertEqual(session.model.reply, "")
        XCTAssertEqual(session.model.phase, .idle)
        XCTAssertNil(session.model.conversationID)
        await waitUntil { stub.streamTerminated }
    }

    func testClosingStopsSpeech() async {
        let speech = StubSpeechSynthesizer()
        let session = QuickAssistantFixture.session(synthesizer: speech)

        session.close()

        XCTAssertGreaterThanOrEqual(speech.stopCalls, 1)
    }

    func testSendAfterCloseIsIgnored() async {
        let stub = QuickAssistantStubConversations()
        let session = QuickAssistantFixture.session(conversations: stub)

        session.close()
        session.send("too late", viaVoice: false)
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(stub.requests.count, 0)
    }

    func testClosingForgetsTheConversation() async {
        let first = QuickAssistantStubConversations()
        first.script = [.token("One"), .done]
        let session = QuickAssistantFixture.session(conversations: first)
        session.send("hello", viaVoice: false)
        await waitUntil { session.model.conversationID != nil && session.model.phase == .idle }

        session.close()

        XCTAssertNil(session.model.conversationID)
    }

    // MARK: - Background

    private func heldTurn(
        recognizer: StubSpeechRecognizer = StubSpeechRecognizer(available: true, authorized: true),
        synthesizer: StubSpeechSynthesizer = StubSpeechSynthesizer(),
        viaVoice: Bool = false
    ) async -> (QuickAssistantSession, QuickAssistantStubConversations) {
        let stub = QuickAssistantStubConversations()
        stub.script = [.token("Partial")]
        stub.holdsStream = true
        let session = QuickAssistantFixture.session(conversations: stub, recognizer: recognizer, synthesizer: synthesizer)
        session.send("hello", viaVoice: viaVoice)
        await waitUntil { session.model.reply == "Partial" }
        return (session, stub)
    }

    func testBackgroundStopsSpeechAndKeepsTheCardAndTheTurn() async {
        let speech = StubSpeechSynthesizer()
        let (session, stub) = await heldTurn(synthesizer: speech)
        // The model silences anything still playing when a turn starts.
        let stopsBefore = speech.stopCalls

        session.enterBackground()

        XCTAssertEqual(speech.stopCalls, stopsBefore + 1)
        XCTAssertEqual(session.prompt, "hello")
        XCTAssertEqual(session.model.phase, .sending)
        XCTAssertEqual(session.model.reply, "Partial")
        XCTAssertFalse(stub.streamTerminated)

        stub.endHeldStream(with: [.token(" reply"), .done])
        await waitUntil { session.model.phase == .idle }
        XCTAssertEqual(session.model.reply, "Partial reply")
        XCTAssertNotNil(session.model.conversationID)
    }

    func testBackgroundDropsAHalfFinishedRecording() async {
        let stub = QuickAssistantStubConversations()
        let recognizer = StubSpeechRecognizer(available: true, authorized: true)
        let session = QuickAssistantFixture.session(conversations: stub, recognizer: recognizer)
        await session.voice.startRecording()
        recognizer.emit("half a sentence")
        try? await Task.sleep(for: .milliseconds(20))

        session.enterBackground()
        XCTAssertEqual(recognizer.stopCalls, 1)

        recognizer.finish()
        await waitUntil { session.voice.state == .idle }
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(stub.requests.count, 0)
        XCTAssertNil(session.prompt)
        XCTAssertNil(session.voice.errorMessage)
    }

    func testVoiceAndSendStillWorkAfterReturning() async {
        let stub = QuickAssistantStubConversations()
        stub.script = [.token("Yes"), .done]
        let recognizer = StubSpeechRecognizer(available: true, authorized: true)
        let session = QuickAssistantFixture.session(conversations: stub, recognizer: recognizer)
        await session.voice.startRecording()
        session.enterBackground()
        recognizer.finish()
        await waitUntil { session.voice.state == .idle }

        session.enterForeground()
        await session.voice.startRecording()
        recognizer.emit("still there?")
        try? await Task.sleep(for: .milliseconds(20))
        session.voice.stopRecording()
        recognizer.finish()

        await waitUntil { session.model.reply == "Yes" }
        XCTAssertEqual(recognizer.startCalls, 2)
        XCTAssertEqual(stub.requests.first?.content, "still there?")
    }

    func testStreamCutOffInTheBackgroundShowsOnReturn() async {
        let (session, stub) = await heldTurn()
        session.enterBackground()

        stub.endHeldStream()

        await waitUntil { session.model.phase != .sending }
        session.enterForeground()
        XCTAssertEqual(session.model.phase, .failed(QuickAssistantGate.cutOffMessage))
        XCTAssertEqual(session.model.reply, "Partial")
    }

    func testStreamFailureInTheBackgroundShowsOnReturn() async {
        let (session, stub) = await heldTurn()
        session.enterBackground()

        stub.endHeldStream(throwing: URLError(.networkConnectionLost))

        await waitUntil { session.model.phase != .sending }
        session.enterForeground()
        guard case .failed = session.model.phase else {
            return XCTFail("expected a failed phase, got \(session.model.phase)")
        }
        XCTAssertEqual(session.model.reply, "Partial")
    }

    func testVoiceReplyFinishingInTheBackgroundIsNotReadOut() async {
        let speech = StubSpeechSynthesizer()
        let (session, stub) = await heldTurn(synthesizer: speech, viaVoice: true)
        session.enterBackground()

        stub.endHeldStream(with: [.done])

        await waitUntil { session.model.phase == .idle }
        session.enterForeground()
        XCTAssertEqual(speech.spokenTexts, [])
    }

    func testVoiceReplyFinishingAfterReturningIsReadOut() async {
        let speech = StubSpeechSynthesizer()
        let (session, stub) = await heldTurn(synthesizer: speech, viaVoice: true)
        session.enterBackground()
        session.enterForeground()

        stub.endHeldStream(with: [.done])

        await waitUntil { speech.spokenTexts == ["Partial"] }
    }
}
