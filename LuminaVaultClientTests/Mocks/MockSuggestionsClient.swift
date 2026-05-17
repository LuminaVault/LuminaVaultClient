// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockSuggestionsClient.swift
// HER-37 — scripted SuggestionsClientProtocol fake.

@testable import LuminaVaultClient
import Foundation

final class MockSuggestionsClient: SuggestionsClientProtocol, @unchecked Sendable {
    var listResult: Result<SuggestionsResponse, Error> = .success(.stubThree)
    private(set) var listCallCount: Int = 0

    func list() async throws -> SuggestionsResponse {
        listCallCount += 1
        return try listResult.get()
    }
}

extension SuggestionsResponse {
    static let stubThree = SuggestionsResponse(suggestions: [
        "What patterns do I have in my Stocks space lately?",
        "Summarize everything I learned about sleep this month",
        "Connect my recent travel notes with my health data",
    ])
}
