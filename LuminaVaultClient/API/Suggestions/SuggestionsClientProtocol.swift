// LuminaVaultClient/LuminaVaultClient/API/Suggestions/SuggestionsClientProtocol.swift
// HER-37: protocol seam for GET /v1/me/suggestions.
import Foundation

protocol SuggestionsClientProtocol: Sendable {
    /// GET /v1/me/suggestions — natural-language query prompts surfaced
    /// above the "Ask Lumina" input bar. Server returns a fixed list at
    /// the scaffold layer; HER-37a swaps in per-user generation.
    func list() async throws -> SuggestionsResponse
}
