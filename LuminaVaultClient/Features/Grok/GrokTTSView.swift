// LuminaVaultClient/LuminaVaultClient/Features/Grok/GrokTTSView.swift
//
// HER-240c — Grok TTS placeholder. Server returns 501 `tts_coming_soon`
// while no upstream audio provider is wired (Hermes docs say Grok's voice
// mode is X-app only at present). View ships now so the iOS surface
// graph doesn't churn when the server starts returning real audio.

import SwiftUI

struct GrokTTSView: View {
    @State private var text: String = ""
    @State private var resultMessage: String?
    @State private var isWorking = false

    init(client _: any GrokClientProtocol) {}

    var body: some View {
        Form {
            Section("Text") {
                TextField("Text to speak…", text: $text, axis: .vertical)
                    .lineLimit(3...8)
            }
            Section {
                Button("Synthesise speech") {
                    isWorking = true
                    resultMessage = "Server hasn't enabled this Grok feature yet (501 tts_coming_soon)."
                    isWorking = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.isEmpty || isWorking)
            } footer: {
                Text("Grok TTS is gated server-side while xAI's audio endpoint is still private. The shape ships now; audio playback lands once the upstream provider is configured.")
            }

            if let resultMessage {
                Section { Text(resultMessage).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Grok TTS")
        .navigationBarTitleDisplayMode(.inline)
    }
}
