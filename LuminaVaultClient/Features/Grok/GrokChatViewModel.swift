// LuminaVaultClient/LuminaVaultClient/Features/Grok/GrokChatViewModel.swift
//
// HER-240c — single-turn Grok chat. Streaming is a future enhancement
// once a streamed Grok surface lands; today this is one prompt, one
// synthesised answer.

import Foundation

@Observable
@MainActor
final class GrokChatViewModel {
    enum State: Equatable, Sendable {
        case idle
        case thinking
        case answered(GrokChatResponse)
        case failed(message: String)
    }

    var prompt: String = ""
    var state: State = .idle

    private let client: any GrokClientProtocol

    init(client: any GrokClientProtocol) {
        self.client = client
    }

    func ask() async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state = .thinking
        do {
            let response = try await client.chat(GrokChatRequest(
                messages: [GrokChatMessage(role: "user", content: trimmed)],
                model: nil,
                stream: nil,
                maxTokens: nil,
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
            default: return "Server returned HTTP \(status)."
            }
        }
        return error.localizedDescription
    }
}
