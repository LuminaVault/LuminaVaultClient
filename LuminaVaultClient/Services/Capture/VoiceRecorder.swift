// LuminaVaultClient/LuminaVaultClient/Services/Capture/VoiceRecorder.swift
//
// Records a voice note to m4a for the capture queue.
//
// m4a because the vault and the transcription endpoint both already accept it
// (`audio/mp4`), and because there is no ffmpeg anywhere in the cluster — if a
// recording needed transcoding to be usable, something would be wrong.
//
// The clip is capped and held in memory rather than streamed: the transcription
// endpoint takes the whole body at once and refuses anything over 10 MB, and a
// recording that is rejected after a long upload is a bad way to find that out.

import AVFoundation
import Foundation
import OSLog

private let log = Logger(subsystem: "com.luminavault", category: "voice-recorder")

@MainActor
@Observable
final class VoiceRecorder {
    /// Beyond this the clip is stopped for you. Long enough for a thought,
    /// short enough to stay inside the endpoint's size limit at m4a bitrates.
    static let maxDuration: TimeInterval = 120

    enum Failure: LocalizedError {
        case permissionDenied
        case unavailable

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Microphone access is off. Turn it on in Settings to record a note."
            case .unavailable:
                return "The microphone isn't available right now."
            }
        }
    }

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0

    /// Called when the duration cap ends the recording on its own.
    ///
    /// Without this the audio is simply lost: `record(forDuration:)` stops the
    /// hardware, the UI notices and flips back to idle, and the next tap starts
    /// a fresh recording over the top of a file nobody saved.
    var onCapReached: ((Data) -> Void)?

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var ticker: Task<Void, Never>?

    /// Asks for permission and starts recording. Throws rather than failing
    /// silently, because a mic button that does nothing is indistinguishable
    /// from a broken one.
    func start() async throws {
        guard !isRecording else { return }

        guard await Self.requestPermission() else { throw Failure.permissionDenied }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            log.error("audio session unavailable: \(error.localizedDescription)")
            throw Failure.unavailable
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lv-voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,          // speech; whisper resamples anyway
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record(forDuration: Self.maxDuration) else { throw Failure.unavailable }
            self.recorder = recorder
            self.fileURL = url
            isRecording = true
            elapsed = 0
            startTicking()
        } catch {
            log.error("could not start recording: \(error.localizedDescription)")
            throw Failure.unavailable
        }
    }

    /// Stops and returns the recorded bytes, or nil if there was nothing to
    /// record. The temporary file is removed either way — the bytes live in the
    /// capture queue from here on.
    @discardableResult
    func stop() -> Data? {
        guard let recorder, let fileURL else { return nil }
        recorder.stop()
        stopTicking()
        isRecording = false
        self.recorder = nil
        self.fileURL = nil

        defer {
            try? FileManager.default.removeItem(at: fileURL)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        let data = try? Data(contentsOf: fileURL)
        return (data?.isEmpty == false) ? data : nil
    }

    /// Throws the recording away, for a cancel rather than a save.
    func discard() {
        _ = stop()
    }

    private func startTicking() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, self.isRecording else { return }
                self.elapsed = self.recorder?.currentTime ?? self.elapsed
                // `record(forDuration:)` stops the hardware at the cap. Collect
                // what was recorded and hand it on — reaching the limit is a
                // finished note, not a discarded one.
                if self.recorder?.isRecording == false {
                    if let audio = self.stop() { self.onCapReached?(audio) }
                    return
                }
            }
        }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    private static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
