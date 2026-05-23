// LuminaVaultClient/LuminaVaultClient/API/DailyReview/DailyReviewHTTPClient.swift
//
// HER-154 scaffold — protocol + concrete HTTP client for the daily
// review digest. Wired in `AppState.makeDailyReviewClient()` (follow-up
// commit once view ships).
import Foundation

protocol DailyReviewClientProtocol: Sendable {
    /// GET /v1/me/today — current digest. Caller controls cadence
    /// (pull-to-refresh + appear); server-side ETag handles 304s.
    func fetchToday() async throws -> DailyReviewDigest
}

final class DailyReviewHTTPClient: DailyReviewClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func fetchToday() async throws -> DailyReviewDigest {
        try await client.execute(DailyReviewEndpoints.GetToday())
    }
}
