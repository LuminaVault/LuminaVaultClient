// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockResurfaceClient.swift
// Scripted `ResurfaceClientProtocol` fake, plus fixtures for the queue.

@testable import LuminaVaultClient
import Foundation
import LuminaVaultShared

// `@unchecked` for the same reason as the other scripted mocks: configured in
// the test body and read from the view model's awaits, all on the main actor.
final class MockResurfaceClient: ResurfaceClientProtocol, @unchecked Sendable {
    var result: Result<ResurfaceResponse, Error>
    private(set) var requestedLimits: [Int] = []

    init(count: Int = 0) {
        result = .success(ResurfaceResponse(items: (0..<count).map { ResurfaceItemDTO.fixture(snippet: "memory \($0)") }))
    }

    func resurface(limit: Int) async throws -> ResurfaceResponse {
        requestedLimits.append(limit)
        return try result.get()
    }
}

extension ResurfaceItemDTO {
    static func fixture(
        id: UUID = UUID(),
        snippet: String = "Decided to keep the API flat until a second client needs nesting.",
        reason: ResurfaceReason = .onThisDay,
        why: String = "Saved a year ago today"
    ) -> ResurfaceItemDTO {
        ResurfaceItemDTO(
            memoryId: id,
            snippet: snippet,
            kind: "decision",
            createdAt: Date(timeIntervalSince1970: 1_730_000_000),
            reason: reason,
            why: why
        )
    }
}

extension ResurfaceQueueViewModel {
    /// A queue over scripted clients that publishes nowhere — tests must not
    /// write the real App Group snapshot.
    @MainActor
    static func stub(
        count: Int = 0,
        fails: Bool = false,
        memoryClient: MockMemoryClient = MockMemoryClient()
    ) -> ResurfaceQueueViewModel {
        let client = MockResurfaceClient(count: count)
        if fails { client.result = .failure(APIError.unauthorized) }
        return ResurfaceQueueViewModel(
            resurfaceClient: client,
            memoryClient: memoryClient,
            publish: { _ in }
        )
    }
}
