// LuminaVaultClient/LuminaVaultClient/Features/Think/ThinkWithLuminaViewModel.swift
// HER-37: drives the "Think with Lumina" tab.
//
// Reuses the existing MemoryQueryClient (POST /v1/query) — the result is
// rendered as an insight card rather than a chat bubble. Suggestion chips
// load from GET /v1/me/suggestions; follow-up chips are hardcoded at
// scaffold-time (HER-37a swaps in dynamic).
import Foundation
import SwiftUI

@Observable
@MainActor
final class ThinkWithLuminaViewModel {
    enum Phase: Equatable {
        case empty
        case querying
        case insight(QueryResponse, queryText: String)
        case failed(message: String)
    }

    enum Event: String {
        case thinkOpened = "her37.think.opened"
        case querySucceeded = "her37.think.query.succeeded"
        case queryFailed = "her37.think.query.failed"
        case followUpTapped = "her37.think.follow_up.tapped"
    }

    private let queryClient: MemoryQueryClientProtocol
    private let suggestionsClient: SuggestionsClientProtocol
    private let resultLimit: Int

    var phase: Phase = .empty
    var queryText: String = ""
    var suggestions: [String] = []

    /// Hardcoded scaffold; HER-37a wires server-generated follow-ups
    /// derived from the active insight's source memories.
    let followUps: [String] = [
        "Go deeper",
        "Turn this into a memo",
        "Show me related notes",
        "Compare with last month",
    ]

    init(
        queryClient: MemoryQueryClientProtocol,
        suggestionsClient: SuggestionsClientProtocol,
        resultLimit: Int = 5,
    ) {
        self.queryClient = queryClient
        self.suggestionsClient = suggestionsClient
        self.resultLimit = resultLimit
    }

    var mascotState: HermieMascotState {
        switch phase {
        case .querying: .thinking
        case .insight: .happy
        case .empty, .failed: .idle
        }
    }

    var isBusy: Bool {
        if case .querying = phase { return true }
        return false
    }

    func loadSuggestions() async {
        do {
            let response = try await suggestionsClient.list()
            suggestions = response.suggestions
        } catch {
            // Non-fatal — the input bar still works; chips just stay hidden.
            suggestions = []
        }
    }

    func applySuggestion(_ text: String) {
        queryText = text
    }

    func tapFollowUp(_ chip: String) {
        // HER-37b will route follow-ups to specific actions (re-query
        // with depth flag, open MemoEditor, etc.). At scaffold the chip
        // text just seeds the input.
        queryText = chip
    }

    func ask() async {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        phase = .querying
        do {
            let response = try await queryClient.query(text: trimmed, limit: resultLimit)
            phase = .insight(response, queryText: trimmed)
        } catch {
            let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message: message)
        }
    }

    /// Pre-fills a MemoRequest from the active insight so the MemoEditor
    /// lands with a sensible default topic / hint. Returns nil when there
    /// is no active insight to memorize.
    func memoSeed() -> MemoRequest? {
        guard case let .insight(_, queryText) = phase else { return nil }
        return MemoRequest(topic: queryText, hint: nil, save: true)
    }
}
