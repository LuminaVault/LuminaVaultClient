// LuminaVaultClient/LuminaVaultClient/Features/Grok/GrokXSearchViewModel.swift
//
// HER-240c — Grok x_search state machine.

import Foundation
import PostHog

@Observable
@MainActor
final class GrokXSearchViewModel {
    enum State: Equatable, Sendable {
        case idle
        case searching
        case results(GrokXSearchResponse)
        case failed(message: String, reconnectRequired: Bool)
    }

    var state: State = .idle
    var query: String = ""

    private let client: any GrokClientProtocol

    init(client: any GrokClientProtocol) {
        self.client = client
    }

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state = .searching
        do {
            let response = try await client.xSearch(GrokXSearchRequest(
                query: trimmed,
                allowedXHandles: nil,
                excludedXHandles: nil,
                fromDate: nil,
                toDate: nil,
                enableImageUnderstanding: nil,
                enableVideoUnderstanding: nil,
            ))
            state = .results(response)
            PostHogSDK.shared.capture("grok_x_search_completed", properties: [
                "citation_count": response.citations.count,
            ])
        } catch {
            state = mapError(error)
        }
    }

    private func mapError(_ error: Error) -> State {
        if case let APIError.httpError(status, _) = error {
            switch status {
            case 402:
                return .failed(message: "Premium tier required. Connect xAI Grok in Settings.", reconnectRequired: true)
            case 409:
                return .failed(message: "Your xAI session has expired. Reconnect to continue.", reconnectRequired: true)
            case 501:
                return .failed(message: "Server hasn't enabled this Grok feature yet.", reconnectRequired: false)
            default:
                return .failed(message: "Server returned HTTP \(status).", reconnectRequired: false)
            }
        }
        return .failed(message: error.localizedDescription, reconnectRequired: false)
    }
}
