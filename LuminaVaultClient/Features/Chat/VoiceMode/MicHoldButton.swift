// LuminaVaultClient/LuminaVaultClient/Features/Chat/VoiceMode/MicHoldButton.swift
//
// HER-153 — Hold-to-talk mic button for the chat composer. Press-down starts
// recording, release stops; the recording animation is purely visual — actual
// state lives on `VoiceModeController`.
import SwiftUI

/// What the mic button knows about the finger on it.
///
/// A touch ends in the button's action too, after its press and release have
/// done the work. Without swallowing that, a release during the permission
/// prompts finds nothing recording and the action starts a second time, with
/// nobody holding. But a touch can also end with no action (a system alert
/// cancels the first press, as does a drag-away), so the swallow expires: it
/// holds while the finger is down and for a moment after it lifts, and a later
/// VoiceOver or keyboard activation is never eaten.
struct MicHoldTracker {
    /// Long enough for the action that follows a lifted finger; far shorter than
    /// any assistive activation that follows a cancelled touch.
    static let activationWindow: TimeInterval = 0.4

    private(set) var isHeld = false
    private var isPressing = false
    private var pressEndedAt: Date?

    /// True when this press should start recording.
    mutating func pressBegan() -> Bool {
        isPressing = true
        pressEndedAt = nil
        guard !isHeld else { return false }
        isHeld = true
        return true
    }

    /// True when this release should stop recording.
    mutating func pressEnded(at now: Date = Date()) -> Bool {
        isPressing = false
        pressEndedAt = now
        guard isHeld else { return false }
        isHeld = false
        return true
    }

    /// The button's action. True when it is the tail of a touch already handled.
    mutating func swallowsActivation(at now: Date = Date()) -> Bool {
        defer { pressEndedAt = nil }
        if isPressing { return true }
        guard let ended = pressEndedAt else { return false }
        return now.timeIntervalSince(ended) <= Self.activationWindow
    }

    /// A recording can end with no release.
    mutating func recordingEnded() {
        isHeld = false
    }

    /// Activation by VoiceOver or keyboard: true when it should start recording.
    mutating func assistiveStart() -> Bool {
        guard !isHeld else { return false }
        isHeld = true
        return true
    }
}

enum MicHoldStart {
    /// Starts recording for a press, unless the finger is already gone. The check
    /// runs before the start, because a release landing before this body runs
    /// finds nothing to stop, and again after, in case it lands during. Neither
    /// check can open the mic for a release during the permission prompts: the
    /// controller drops that start itself.
    @MainActor
    static func run(voice: VoiceModeController, isHeld: () -> Bool) async {
        guard isHeld() else { return }
        await voice.startRecording()
        if !isHeld(), voice.isRecording { voice.stopRecording() }
    }
}

struct MicHoldButton: View {
    @Environment(\.lvPalette) private var palette
    @Bindable var voice: VoiceModeController
    @State private var tracker = MicHoldTracker()

    var body: some View {
        // A real `Button`, not a bare `Image` with a `DragGesture` attached.
        // The old form had no button semantics at all, so VoiceOver could not
        // activate it and it took no part in focus or the accessibility tree
        // beyond the label it carried.
        Button {
            // Hold drives recording; the plain activation path exists so
            // VoiceOver and Full Keyboard Access can still toggle it.
            if !tracker.swallowsActivation() {
                toggleForAssistiveActivation()
            }
        } label: {
            LVIconView(
                voice.isRecording ? .micCircleFill : .micFill,
                size: voice.isRecording ? 28 : 20,
                tint: voice.isRecording ? palette.accent : palette.glowPrimary
            )
            .scaleEffect(voice.isRecording ? 1.1 : 1.0)
            .frame(minWidth: LVSize.tapTarget, minHeight: LVSize.tapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // `isEnabled` was never consulted anywhere — the control stayed live
        // even after the recognizer reported itself unavailable or the user
        // denied permission, so a press just failed silently.
        .disabled(!voice.isEnabled)
        .opacity(voice.isEnabled ? 1 : 0.4)
        .lvAnimation(LVMotion.quick, value: voice.isRecording)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            if pressing {
                guard voice.isEnabled else { return }
                startIfNeeded()
            } else {
                // Not gated on `isEnabled`: a denial during the hold turns it off,
                // and a release that did not clear `isHeld` would leave a dead mic.
                stopIfNeeded()
            }
        }, perform: {})
        // Was a raw `UIImpactFeedbackGenerator` inside the controller, which
        // ignored the user's haptics setting. `.sensoryFeedback` honours it.
        .sensoryFeedback(.impact(weight: .medium), trigger: voice.recordingStartTrigger)
        // A recording can end with no release: a recognizer error, or the app
        // leaving the screen.
        .onChange(of: voice.isRecording) { _, recording in
            if !recording { tracker.recordingEnded() }
        }
        .accessibilityLabel(voice.isRecording ? "Stop recording" : "Hold to talk")
        .accessibilityHint("Press and hold to record, release to send.")
        .accessibilityAddTraits(voice.isRecording ? [.isButton, .isSelected] : .isButton)
    }

    private func startIfNeeded() {
        guard tracker.pressBegan() else { return }
        startRecordingWhileHeld()
    }

    private func stopIfNeeded() {
        guard tracker.pressEnded() else { return }
        voice.stopRecording()
    }

    private func startRecordingWhileHeld() {
        Task { await MicHoldStart.run(voice: voice, isHeld: { tracker.isHeld }) }
    }

    /// VoiceOver activation is a single tap, not a press-and-hold, so it maps
    /// to start-then-stop rather than being unusable.
    private func toggleForAssistiveActivation() {
        if voice.isRecording {
            tracker.recordingEnded()
            voice.stopRecording()
        } else if tracker.assistiveStart() {
            Task {
                await voice.startRecording()
                // No release follows this activation to clear it.
                if !voice.isRecording { tracker.recordingEnded() }
            }
        }
    }
}
