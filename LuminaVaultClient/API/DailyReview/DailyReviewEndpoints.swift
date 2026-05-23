// LuminaVaultClient/LuminaVaultClient/API/DailyReview/DailyReviewEndpoints.swift
//
// HER-154 scaffold — server contract:
//   GET /v1/me/today  -> MeTodayResponse (HER-206, server-shipped)
//
// Until LuminaVaultShared exposes `MeTodayResponse` we decode into the
// local `DailyReviewDigest` mirror. The server speaks snake_case; the
// shared `JSONDecoder.hvDefault` already handles that via
// `.convertFromSnakeCase`.
import Foundation

enum DailyReviewEndpoints {
    struct GetToday: Endpoint {
        typealias Response = DailyReviewDigest
        var path: String { "/v1/me/today" }
        var method: HTTPMethod { .get }
    }
}
