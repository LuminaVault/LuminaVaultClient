// LuminaVaultClient/LuminaVaultClient/Features/Chat/VoiceMode/MicHoldButton.swift
//
// HER-153 — Hold-to-talk mic button for the chat composer. Press-down starts
// recording, release stops; the recording animation is purely visual — actual
// state lives on `VoiceModeController`.
import SwiftUI

struct MicHoldButton: View {
    @Environment(\.lvPalette) private var palette
    @Bindable var voice: VoiceModeController
    @State private var isHeld = false

    var body: some View {
        // A real `Button`, not a bare `Image` with a `DragGesture` attached.
        // The old form had no button semantics at all, so VoiceOver could not
        // activate it and it took no part in focus or the accessibility tree
        // beyond the label it carried.
        Button {
            // Hold drives recording; the plain activation path exists so
            // VoiceOver and Full Keyboard Access can still toggle it.
            toggleForAssistiveActivation()
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
            guard voice.isEnabled else { return }
            if pressing {
                startIfNeeded()
            } else {
                stopIfNeeded()
            }
        }, perform: {})
        // Was a raw `UIImpactFeedbackGenerator` inside the controller, which
        // ignored the user's haptics setting. `.sensoryFeedback` honours it.
        .sensoryFeedback(.impact(weight: .medium), trigger: voice.recordingStartTrigger)
        .accessibilityLabel(voice.isRecording ? "Stop recording" : "Hold to talk")
        .accessibilityHint("Press and hold to record, release to send.")
        .accessibilityAddTraits(voice.isRecording ? [.isButton, .isSelected] : .isButton)
    }

    private func startIfNeeded() {
        guard !isHeld else { return }
        isHeld = true
        Task { await voice.startRecording() }
    }

    private func stopIfNeeded() {
        guard isHeld else { return }
        isHeld = false
        voice.stopRecording()
    }

    /// VoiceOver activation is a single tap, not a press-and-hold, so it maps
    /// to start-then-stop rather than being unusable.
    private func toggleForAssistiveActivation() {
        if voice.isRecording {
            stopIfNeeded()
        } else if !isHeld {
            isHeld = true
            Task { await voice.startRecording() }
        }
    }
}
