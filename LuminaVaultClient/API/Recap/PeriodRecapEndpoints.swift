// LuminaVaultClient/LuminaVaultClient/API/Recap/PeriodRecapEndpoints.swift
//
// GET /v1/me/recap/period?period=year|month&year=YYYY[&month=1-12] — the
// year or month in review, as a deck of cards.
//
// The response is the shared `PeriodRecapResponse`. The server writes
// camelCase keys and every list is an array (never a map keyed by a tag), so
// the default `.convertFromSnakeCase` decoder leaves it as written.

import Foundation
import LuminaVaultShared

/// What a recap is asked for. UI-only.
nonisolated struct PeriodRecapRequest: Equatable, Hashable, Identifiable, Sendable {
    let period: RecapPeriodKind
    let year: Int
    /// 1–12, only for `.month`.
    let month: Int?

    var id: String {
        queryPath
    }

    static func year(_ year: Int) -> Self {
        Self(period: .year, year: year, month: nil)
    }

    static func month(_ month: Int, of year: Int) -> Self {
        Self(period: .month, year: year, month: month)
    }

    /// This year, or this month, in `calendar`.
    static func current(_ period: RecapPeriodKind, now: Date = Date(), calendar: Calendar = .current) -> Self {
        let parts = calendar.dateComponents([.year, .month], from: now)
        let year = parts.year ?? 2026
        return period == .month ? .month(parts.month ?? 1, of: year) : .year(year)
    }

    var queryPath: String {
        var path = "/v1/me/recap/period?period=\(period.rawValue)&year=\(year)"
        if period == .month, let month { path += "&month=\(month)" }
        return path
    }
}

protocol PeriodRecapClientProtocol: Sendable {
    func periodRecap(_ request: PeriodRecapRequest) async throws -> PeriodRecapResponse
}

nonisolated enum PeriodRecapEndpoints {
    nonisolated struct Get: Endpoint {
        typealias Response = PeriodRecapResponse
        let request: PeriodRecapRequest

        var path: String {
            request.queryPath
        }

        var method: HTTPMethod {
            .get
        }
    }
}

final class PeriodRecapHTTPClient: PeriodRecapClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) {
        self.client = client
    }

    func periodRecap(_ request: PeriodRecapRequest) async throws -> PeriodRecapResponse {
        try await client.execute(PeriodRecapEndpoints.Get(request: request))
    }
}
