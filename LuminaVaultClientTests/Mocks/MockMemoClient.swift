// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockMemoClient.swift
// HER-37 — scripted MemoClientProtocol fake.

@testable import LuminaVaultClient
import Foundation

final class MockMemoClient: MemoClientProtocol, @unchecked Sendable {
    var generateResult: Result<MemoResponse, Error> = .success(.stub)
    var listResult: Result<MemoListResponse, Error> = .success(.empty)
    private(set) var generateCalls: [MemoRequest] = []
    private(set) var listCallCount: Int = 0

    func generate(_ request: MemoRequest) async throws -> MemoResponse {
        generateCalls.append(request)
        return try generateResult.get()
    }

    func list() async throws -> MemoListResponse {
        listCallCount += 1
        return try listResult.get()
    }
}

extension MemoResponse {
    static let stub = MemoResponse(
        memo: "## Synthesized memo\n\nA short synthesis body.",
        path: "memos/2026-05-17/sleep-patterns.md",
        sourceMemoryIds: [UUID()],
        summary: "Two related memories synthesised.",
    )
}

extension MemoListResponse {
    static let empty = MemoListResponse(memos: [])
    static let stubTwoMemos = MemoListResponse(memos: [
        MemoSummaryDTO(
            id: UUID(),
            title: "Sleep Patterns",
            path: "memos/2026-05-17/sleep-patterns.md",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            summary: "Two related memories synthesised.",
        ),
        MemoSummaryDTO(
            id: UUID(),
            title: "Travel And Health",
            path: "memos/2026-05-16/travel-and-health.md",
            createdAt: Date(timeIntervalSince1970: 1_699_900_000),
            summary: nil,
        ),
    ])
}
