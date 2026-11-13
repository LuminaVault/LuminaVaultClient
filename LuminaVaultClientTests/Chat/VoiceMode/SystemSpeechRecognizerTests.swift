// LuminaVaultClient/LuminaVaultClientTests/Chat/VoiceMode/SystemSpeechRecognizerTests.swift
//
// Audio buffers arrive on a realtime thread. A tap block that inherits the main
// actor traps there on the first buffer, which takes the test process down with
// it. So this renders real audio through a real tap, with no microphone: an
// offline engine and a player node.
//
// The two permission closures have no test. They run inside system calls that
// show a prompt on a device nobody has answered, and they have no seam short of
// wrapping those calls for the sake of the test.
import AVFoundation
@testable import LuminaVaultClient
import Speech
import XCTest

@MainActor
final class SystemSpeechRecognizerTests: XCTestCase {
    /// Reports the buffers the tap hands over, from whichever thread that is.
    nonisolated private final class RecordingRequest: SFSpeechAudioBufferRecognitionRequest, @unchecked Sendable {
        // @unchecked: only `onAppend` is added. It is set before audio starts.
        var onAppend: (@Sendable (_ onMainThread: Bool) -> Void)?

        override func append(_: AVAudioPCMBuffer) {
            onAppend?(Thread.isMainThread)
        }
    }

    /// @unchecked: handed to one background queue, and the test waits for it.
    nonisolated private struct OfflineRender: @unchecked Sendable {
        let engine: AVAudioEngine
        let output: AVAudioPCMBuffer

        /// Renders on the calling thread and returns the first render error, so
        /// the caller learns the render ended before it touches the engine.
        func run() -> (any Error)? {
            for _ in 0 ..< 8 {
                do {
                    _ = try engine.renderOffline(output.frameCapacity, to: output)
                } catch {
                    return error
                }
            }
            return nil
        }
    }

    /// @unchecked: written once by the render queue, read after the test waited for it.
    nonisolated private final class RenderErrorBox: @unchecked Sendable {
        private let lock = NSLock()
        private var error: (any Error)?

        func set(_ newValue: (any Error)?) {
            lock.withLock { error = newValue }
        }

        func get() -> (any Error)? {
            lock.withLock { error }
        }
    }

    func testTapDeliversBuffersOffTheMainThreadWithoutTrapping() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)

        let audio = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100))
        audio.frameLength = 44100
        let output = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ))

        let delivered = expectation(description: "a buffer reached the request")
        delivered.assertForOverFulfill = false
        let request = RecordingRequest()
        request.onAppend = { onMainThread in
            XCTAssertFalse(onMainThread)
            delivered.fulfill()
        }
        SystemSpeechRecognizer.installTap(on: engine.mainMixerNode, format: format, feeding: request)

        try engine.start()
        player.scheduleBuffer(audio)
        player.play()

        let render = OfflineRender(engine: engine, output: output)
        let rendered = expectation(description: "the render finished")
        let renderError = RenderErrorBox()
        DispatchQueue.global(qos: .userInitiated).async {
            renderError.set(render.run())
            rendered.fulfill()
        }
        // The engine is stopped only once the render has ended: stopping it
        // under a render still running on the background queue can crash the host.
        wait(for: [delivered, rendered], timeout: 10)
        XCTAssertNil(renderError.get(), "the offline render failed")

        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
    }
}
