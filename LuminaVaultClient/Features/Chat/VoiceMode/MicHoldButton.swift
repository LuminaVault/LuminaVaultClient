// LuminaVaultClient/LuminaVaultClient/Features/Chat/VoiceMode/MicHoldButton.swift
//
// HER-153 — Hold-to-talk mic button for the chat composer. Replaces
// the empty `Image(systemName: "mic.fill")` stub. Press-down starts
// recording, release stops; the recording animation is purely visual
// — actual state lives on `VoiceModeController`.
import SwiftUI

struct MicHoldButton: View {
    @Environment(\.lvPalette) private var palette
    @Bindable var voice: VoiceModeController
    @State private var isHeld = false

    var body: some View {
        // HER-291: kept as Image — runtime symbol name (mic.circle.fill not in LVIcon)
        Image(systemName: voice.isRecording ? "mic.circle.fill" : "mic.fill")
            .font(.system(size: voice.isRecording ? 28 : 20))
            .foregroundStyle(voice.isRecording ? palette.accent : palette.glowPrimary)
            .scaleEffect(voice.isRecording ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.18), value: voice.isRecording)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isHeld {
                            isHeld = true
                            Task { await voice.startRecording() }
                        }
                    }
                    .onEnded { _ in
                        isHeld = false
                        voice.stopRecording()
                    },
            )
            .accessibilityLabel("Hold to talk")
            .accessibilityHint("Press and hold to record, release to send.")
    }
}
