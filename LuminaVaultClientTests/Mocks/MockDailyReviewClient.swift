// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockDailyReviewClient.swift
// Scripted `DailyReviewClientProtocol` fake. The digest's `memories` are what
// Home counts as "to revisit".

@testable import LuminaVaultClient
import Foundation
import LuminaVaultShared

final class MockDailyReviewClient: DailyReviewClientProtocol, @unchecked Sendable {
    var result: Result<DailyReviewDigest, Error> = .success(DailyReviewDigest(date: .now))
    private(set) var callCount = 0

    init(memories: Int = 0) {
        result = .success(
            DailyReviewDigest(
                date: .now,
                memories: (0..<memories).map { index in
                    QueryHitDTO(
                        id: UUID(),
                        content: "memo \(index)",
                        distance: 0.1,
                        createdAt: .now
                    )
                }
            )
        )
    }

    func fetchToday() async throws -> DailyReviewDigest {
        callCount += 1
        return try result.get()
    }
}
