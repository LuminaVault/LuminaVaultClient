// LuminaVaultClient/LuminaVaultClientTests/Chat/VoiceMode/VoiceModeControllerTests.swift
//
// HER-153 — Exercises the VoiceModeController state machine with
// stubbed recognizer + synthesizer. No real audio APIs touched.
import XCTest
@testable import LuminaVaultClient

@MainActor
final class VoiceModeControllerTests: XCTestCase {

    func testStartRecordingEmitsPartialsAndFiresFinalTranscript() async throws {
        let recognizer = StubSpeechRecognizer(available: true, authorized: true)
        let synth = StubSpeechSynthesizer()
        let controller = VoiceModeController(recognizer: recognizer, synthesizer: synth)

        var finalTranscripts: [String] = []
        controller.onFinalTranscript = { finalTranscripts.append($0) }

        await controller.startRecording()
        XCTAssertEqual(controller.state, .recording)

        recognizer.emit("hello")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(controller.liveTranscript, "hello")

        recognizer.emit("hello world")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(controller.liveTranscript, "hello world")

        controller.stopRecording()
        recognizer.finish()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(finalTranscripts, ["hello world"])
        XCTAssertEqual(controller.liveTranscript, "")
        XCTAssertNil(controller.errorMessage)
    }

    func testEmptyTranscriptSurfacesErrorInsteadOfFiringCallback() async throws {
        let recognizer = StubSpeechRecognizer(available: true, authorized: true)
        let controller = VoiceModeController(recognizer: recognizer, synthesizer: StubSpeechSynthesizer())
        var fired = false
        controller.onFinalTranscript = { _ in fired = true }

        await controller.startRecording()
        controller.stopRecording()
        recognizer.finish()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(fired)
        XCTAssertEqual(controller.errorMessage, "Didn't catch that. Try again.")
        XCTAssertEqual(controller.state, .idle)
    }

    func testShutDownDropsTheFinalTranscript() async throws {
        let recognizer = StubSpeechRecognizer(available: true, authorized: true)
        let controller = VoiceModeController(recognizer: recognizer, synthesizer: StubSpeechSynthesizer())
        var fired = false
        controller.onFinalTranscript = { _ in fired = true }

        await controller.startRecording()
        recognizer.emit("half a sentence")
        try await Task.sleep(for: .milliseconds(20))
        controller.shutDown()
        recognizer.finish()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(fired)
        XCTAssertEqual(recognizer.stopCalls, 1)
        XCTAssertEqual(controller.state, .idle)
    }

    func testStartAfterShutDownNeverOpensTheMic() async {
        let recognizer = StubSpeechRecognizer(available: true, authorized: true)
        let controller = VoiceModeController(recognizer: recognizer, synthesizer: StubSpeechSynthesizer())

        controller.shutDown()
        await controller.startRecording()

        XCTAssertEqual(recognizer.startCalls, 0)
        XCTAssertEqual(controller.state, .idle)
    }

    /// The permission prompt can be up while the owner of the controller goes
    /// away. Granting it afterwards must not open the mic.
    func testShutDownDuringThePermissionPromptNeverOpensTheMic() async {
        let recognizer = GatedAuthorizationRecognizer()
        let controller = VoiceModeController(recognizer: recognizer, synthesizer: StubSpeechSynthesizer())

        let start = Task { await controller.startRecording() }
        await recognizer.waitForPrompt()
        controller.shutDown()
        recognizer.grant()
        await start.value

        XCTAssertEqual(recognizer.startCalls, 0)
        XCTAssertEqual(controller.state, .idle)
    }

    func testDeniedPermissionSurfacesError() async throws {
        let recognizer = StubSpeechRecognizer(available: true, authorized: false)
        let controller = VoiceModeController(recognizer: recognizer, synthesizer: StubSpeechSynthesizer())

        await controller.startRecording()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertTrue(controller.errorMessage?.contains("Settings") ?? false)
    }

    func testSpeakDrivesSpeakingStateAndStopRestoresIdle() async throws {
        let synth = StubSpeechSynthesizer()
        let controller = VoiceModeController(
            recognizer: StubSpeechRecognizer(available: true, authorized: true),
            synthesizer: synth,
        )

        controller.speak("hi there")
        XCTAssertEqual(controller.state, .speaking)
        XCTAssertEqual(synth.spokenTexts, ["hi there"])

        synth.finishCurrent()
        XCTAssertEqual(controller.state, .idle)
    }

    func testStopSpeakingForcesIdle() async throws {
        let synth = StubSpeechSynthesizer()
        let controller = VoiceModeController(
            recognizer: StubSpeechRecognizer(available: true, authorized: true),
            synthesizer: synth,
        )
        controller.speak("a long message")
        XCTAssertEqual(controller.state, .speaking)

        controller.stopSpeaking()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(synth.stopCalls, 1)
    }
}

// MARK: - Stubs

/// Holds `requestAuthorization()` open, like a system prompt nobody has answered.
@MainActor
private final class GatedAuthorizationRecognizer: SpeechRecognizing {
    let isAvailable = true
    private(set) var startCalls = 0
    private var prompt: CheckedContinuation<Bool, Never>?

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { prompt = $0 }
    }

    func waitForPrompt() async {
        while prompt == nil {
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    func grant() {
        prompt?.resume(returning: true)
        prompt = nil
    }

    func start() throws -> AsyncThrowingStream<String, Error> {
        startCalls += 1
        return AsyncThrowingStream { $0.finish() }
    }

    func stop() {}
}

@MainActor
final class StubSpeechRecognizer: SpeechRecognizing {
    var isAvailable: Bool
    private let authorized: Bool
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    private(set) var startCalls = 0
    private(set) var stopCalls = 0

    init(available: Bool, authorized: Bool) {
        self.isAvailable = available
        self.authorized = authorized
    }

    func requestAuthorization() async -> Bool { authorized }

    func start() throws -> AsyncThrowingStream<String, Error> {
        startCalls += 1
        return AsyncThrowingStream { continuation in
            self.continuation = continuation
        }
    }

    func stop() {
        stopCalls += 1
    }

    func emit(_ transcript: String) {
        continuation?.yield(transcript)
    }

    func finish() {
        continuation?.finish()
        continuation = nil
    }

    func fail(_ error: Error) {
        continuation?.finish(throwing: error)
        continuation = nil
    }
}

@MainActor
final class StubSpeechSynthesizer: SpeechSynthesizing {
    var isSpeaking: Bool = false
    private(set) var spokenTexts: [String] = []
    private(set) var stopCalls = 0
    private var onStart: (@MainActor () -> Void)?
    private var onFinish: (@MainActor () -> Void)?

    func speak(
        _ text: String,
        onStart: @escaping @MainActor () -> Void,
        onFinish: @escaping @MainActor () -> Void,
    ) {
        spokenTexts.append(text)
        isSpeaking = true
        self.onStart = onStart
        self.onFinish = onFinish
        onStart()
    }

    func stop() {
        stopCalls += 1
        isSpeaking = false
        let finishCallback = onFinish
        onStart = nil
        onFinish = nil
        finishCallback?()
    }

    func finishCurrent() {
        isSpeaking = false
        let finishCallback = onFinish
        onStart = nil
        onFinish = nil
        finishCallback?()
    }
}
