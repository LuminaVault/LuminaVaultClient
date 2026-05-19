// LuminaVaultClient/LuminaVaultClient/Features/Grok/GrokVisionViewModel.swift
//
// HER-240c — minimal Grok vision flow. iOS user pastes a public image
// URL plus a prompt; server forwards to Grok 4.3 multimodal.

import Foundation

@Observable
@MainActor
final class GrokVisionViewModel {
    enum State: Equatable, Sendable {
        case idle
        case analysing
        case answered(GrokVisionResponse)
        case failed(message: String)
    }

    var imageURL: String = ""
    var prompt: String = "Describe this image."
    var state: State = .idle

    private let client: any GrokClientProtocol

    init(client: any GrokClientProtocol) {
        self.client = client
    }

    func analyse() async {
        let trimmedURL = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedPrompt.isEmpty else { return }
        state = .analysing
        do {
            let response = try await client.vision(GrokVisionRequest(
                prompt: trimmedPrompt,
                imageURLs: [trimmedURL],
            ))
            state = .answered(response)
        } catch {
            state = .failed(message: errorMessage(error))
        }
    }

    private func errorMessage(_ error: Error) -> String {
        if case let APIError.httpError(status, _) = error {
            switch status {
            case 402: return "Premium tier required. Connect xAI Grok in Settings."
            case 409: return "Your xAI session has expired. Reconnect to continue."
            case 400: return "Server rejected the image URL or prompt."
            default: return "Server returned HTTP \(status)."
            }
        }
        return error.localizedDescription
    }
}
