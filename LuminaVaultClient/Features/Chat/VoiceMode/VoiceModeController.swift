// LuminaVaultClient/LuminaVaultClient/Features/Chat/VoiceMode/VoiceModeController.swift
//
// HER-153 — @Observable orchestrator for chat voice mode. Owns the
// recording/speaking state machine, the live transcript buffer, and a
// user-visible error banner. The composer view observes `state` and
// `errorMessage`; ChatViewModel observes `onFinalTranscript` to feed
// transcripts into the send pipeline.
import Foundation
import UIKit

@Observable
@MainActor
final class VoiceModeController {
    enum State: Equatable, Sendable {
        case idle
        case recording
        case speaking
    }

    private(set) var state: State = .idle
    private(set) var liveTranscript: String = ""
    private(set) var errorMessage: String?
    /// True once the user has both granted mic + speech permission
    /// during this app session. Without it the mic button stays
    /// enabled (so first-press triggers the prompt) but `isEnabled` is
    /// false the moment the prompt is denied.
    private(set) var hasPermission: Bool = false

    private let recognizer: any SpeechRecognizing
    private let synthesizer: any SpeechSynthesizing
    private var recognitionTask: Task<Void, Never>?
    private var errorDecayTask: Task<Void, Never>?

    /// Wired by ChatViewModel — fires once per successful release with
    /// the final transcript. Empty transcripts are dropped (no-op).
    var onFinalTranscript: ((String) -> Void)?

    init(
        recognizer: any SpeechRecognizing = SystemSpeechRecognizer(),
        synthesizer: any SpeechSynthesizing = SystemSpeechSynthesizer(),
    ) {
        self.recognizer = recognizer
        self.synthesizer = synthesizer
    }

    var isEnabled: Bool {
        recognizer.isAvailable && errorMessage == nil
    }

    var isRecording: Bool { state == .recording }
    var isSpeaking: Bool { state == .speaking }

    // MARK: - Recording

    func startRecording() async {
        guard state == .idle else { return }
        clearError()
        if !hasPermission {
            let granted = await recognizer.requestAuthorization()
            hasPermission = granted
            guard granted else {
                setError("Enable Microphone & Speech Recognition in Settings to talk to Lumina.")
                return
            }
        }
        guard recognizer.isAvailable else {
            setError("Speech recognition is unavailable right now.")
            return
        }
        do {
            let stream = try recognizer.start()
            state = .recording
            liveTranscript = ""
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            recognitionTask = Task { [weak self] in
                await self?.consume(stream: stream)
            }
        } catch {
            setError(Self.message(for: error))
            state = .idle
        }
    }

    func stopRecording() {
        guard state == .recording else { return }
        recognizer.stop()
        // The recognizer's final result still arrives via the stream.
        // We finalize there to ensure onFinalTranscript fires with the
        // last partial baked in.
    }

    private func consume(stream: AsyncThrowingStream<String, Error>) async {
        do {
            for try await transcript in stream {
                liveTranscript = transcript
            }
            finalizeTranscript()
        } catch {
            setError(Self.message(for: error))
            state = .idle
        }
    }

    private func finalizeTranscript() {
        let final = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        state = .idle
        if final.isEmpty {
            setError("Didn't catch that. Try again.")
        } else {
            onFinalTranscript?(final)
        }
        liveTranscript = ""
    }

    // MARK: - Speaking

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        clearError()
        state = .speaking
        synthesizer.speak(
            trimmed,
            onStart: { [weak self] in
                self?.state = .speaking
            },
            onFinish: { [weak self] in
                guard let self else { return }
                if self.state == .speaking { self.state = .idle }
            },
        )
    }

    func stopSpeaking() {
        synthesizer.stop()
        if state == .speaking { state = .idle }
    }

    // MARK: - Error surface

    private func setError(_ message: String) {
        errorMessage = message
        errorDecayTask?.cancel()
        errorDecayTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            await MainActor.run { self?.errorMessage = nil }
        }
    }

    private func clearError() {
        errorDecayTask?.cancel()
        errorMessage = nil
    }

    private static func message(for error: Error) -> String {
        if let rec = error as? SpeechRecognizerError {
            switch rec {
            case .unavailable: return "Speech recognition is unavailable right now."
            case .notAuthorized: return "Enable Microphone & Speech Recognition in Settings to talk to Lumina."
            case .audioSessionFailed: return "Couldn't open the microphone. Try again."
            case .engineFailed: return "Audio engine failed to start. Try again."
            case .noSpeechDetected: return "Didn't catch that. Try again."
            }
        }
        return "Voice input failed. Try again."
    }
}
