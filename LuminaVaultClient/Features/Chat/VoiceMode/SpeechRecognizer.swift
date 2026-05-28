// LuminaVaultClient/LuminaVaultClient/Features/Chat/VoiceMode/SpeechRecognizer.swift
//
// HER-153 — On-device speech recognition for the chat composer's
// hold-to-talk mic. Wraps `SFSpeechRecognizer` +
// `SFSpeechAudioBufferRecognitionRequest` + `AVAudioEngine` so the rest
// of the voice-mode stack only depends on a protocol — tests stub it
// instead of opening a microphone.
import AVFoundation
import Foundation
import Speech

enum SpeechRecognizerError: Error, Equatable {
    case unavailable
    case notAuthorized
    case audioSessionFailed(String)
    case engineFailed(String)
    case noSpeechDetected
}

@MainActor
protocol SpeechRecognizing: AnyObject, Sendable {
    var isAvailable: Bool { get }
    func requestAuthorization() async -> Bool
    /// Start a recognition session. Yields incremental transcripts as
    /// the user speaks. Throws on engine/audio-session failure or when
    /// the session ends without any speech detected.
    func start() throws -> AsyncThrowingStream<String, Error>
    /// Stop the recognition session. The async stream finishes after
    /// emitting one final transcript.
    func stop()
}

@MainActor
final class SystemSpeechRecognizer: SpeechRecognizing, @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    var isAvailable: Bool {
        recognizer?.isAvailable == true
    }

    func requestAuthorization() async -> Bool {
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechOK else { return false }
        return await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    func start() throws -> AsyncThrowingStream<String, Error> {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechRecognizerError.unavailable
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechRecognizerError.audioSessionFailed(error.localizedDescription)
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            cleanup()
            throw SpeechRecognizerError.engineFailed(error.localizedDescription)
        }

        let stream = AsyncThrowingStream<String, Error> { continuation in
            self.continuation = continuation
            self.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let transcript = result.bestTranscription.formattedString
                    continuation.yield(transcript)
                    if result.isFinal {
                        continuation.finish()
                        Task { @MainActor in self.cleanup() }
                    }
                }
                if let error {
                    continuation.finish(throwing: error)
                    Task { @MainActor in self.cleanup() }
                }
            }
        }
        return stream
    }

    func stop() {
        request?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        // Task callback finalizes the stream and calls cleanup.
    }

    private func cleanup() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        task?.cancel()
        task = nil
        request = nil
        continuation = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
