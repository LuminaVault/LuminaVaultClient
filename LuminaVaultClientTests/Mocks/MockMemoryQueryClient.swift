// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockMemoryQueryClient.swift
//
// HER-157 — scripted MemoryQueryClientProtocol fake.

@testable import LuminaVaultClient
import Foundation

final class MockMemoryQueryClient: MemoryQueryClientProtocol, @unchecked Sendable {
    var queryResult: Result<QueryResponse, Error> = .success(.empty)
    private(set) var calls: [(text: String, limit: Int?)] = []

    func query(text: String, limit: Int?) async throws -> QueryResponse {
        calls.append((text, limit))
        return try queryResult.get()
    }
}

extension QueryResponse {
    static let empty = QueryResponse(summary: "No matching memories.", hits: [])
    static let stubTwoHits = QueryResponse(
        summary: "Two related memories found.",
        hits: [
            QueryHitDTO(id: UUID(), content: "first memory body", distance: 0.10, createdAt: Date(timeIntervalSince1970: 1_700_000_000)),
            QueryHitDTO(id: UUID(), content: "second memory body", distance: 0.31, createdAt: nil),
        ],
    )
}
