// LuminaVaultClient/LuminaVaultClient/Features/Chat/VoiceMode/SpeechSynthesizer.swift
//
// HER-153 — On-device TTS for Lumina's reply. Wraps
// `AVSpeechSynthesizer` so the controller only depends on a protocol
// and tests can stub state transitions without touching real audio.
//
// Voice tuning: HER-153 calls for "slower rate, slight reverb if
// possible". Reverb needs AVAudioEngine + AVAudioUnitReverb routing
// (deferred). Here we slow the rate to ~0.45 and prefer an enhanced /
// premium en-US voice so Lumina sounds more natural than the default.
import AVFoundation
import Foundation

@MainActor
protocol SpeechSynthesizing: AnyObject, Sendable {
    var isSpeaking: Bool { get }
    func speak(_ text: String, onStart: @escaping @MainActor () -> Void, onFinish: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor
final class SystemSpeechSynthesizer: NSObject, SpeechSynthesizing, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private var onStart: (@MainActor () -> Void)?
    private var onFinish: (@MainActor () -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    func speak(
        _ text: String,
        onStart: @escaping @MainActor () -> Void,
        onFinish: @escaping @MainActor () -> Void,
    ) {
        guard !text.isEmpty else {
            onStart()
            onFinish()
            return
        }
        self.onStart = onStart
        self.onFinish = onFinish

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.preferredVoice()
        utterance.rate = 0.45
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.1

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in onStart?() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            onFinish?()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            onFinish?()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Pick the highest-quality en-US voice available. iOS bundles a
    /// default voice always; enhanced / premium voices ship only after
    /// the user downloads them from Settings → Accessibility → Spoken
    /// Content. We grade them and fall back gracefully.
    private static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("en")
        }
        if let premium = voices.first(where: { $0.quality == .premium }) {
            return premium
        }
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }
}
