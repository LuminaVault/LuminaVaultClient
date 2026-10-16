// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockRecapClient.swift
// Scripted `RecapClientProtocol` fake: one result per range, every call
// recorded so a test can assert which range was asked for.

@testable import LuminaVaultClient
import Foundation
import LuminaVaultShared

// `@unchecked` because the fake is mutated from the test body and read from
// the view model's awaits; every test drives it from the main actor, so the
// accesses never overlap. Same shape as `MockHomeSummaryClient`.
final class MockRecapClient: RecapClientProtocol, @unchecked Sendable {
    var results: [AnalyticsRange: Result<MeRecapResponse, Error>] = [:]
    private(set) var requestedRanges: [AnalyticsRange] = []

    func recap(range: AnalyticsRange) async throws -> MeRecapResponse {
        requestedRanges.append(range)
        guard let result = results[range] else { throw APIError.httpError(statusCode: 404, data: Data()) }
        return try result.get()
    }
}

extension MeRecapResponse {
    /// A recap with the given totals and a flat daily series. `previous`
    /// defaults to all zeros.
    static func fixture(
        range: AnalyticsRange = .week,
        start: String = "2026-10-09",
        end: String = "2026-10-15",
        timezone: String = "Europe/Lisbon",
        totals: RecapTotalsDTO = RecapTotalsDTO(captures: 12, learned: 4, asked: 6, reviewed: 3, activeDays: 5, streakDays: 3),
        previous: RecapTotalsDTO = RecapTotalsDTO(),
        daily: [RecapDayDTO]? = nil,
        kinds: RecapKindsDTO = RecapKindsDTO(preference: 1, decision: 2, fact: 3, note: 0),
        highlights: [RecapHighlightDTO] = [],
        shareText: String = "My week in LuminaVault: 12 captures, 4 learned."
    ) -> MeRecapResponse {
        MeRecapResponse(
            range: range,
            start: start,
            end: end,
            timezone: timezone,
            totals: totals,
            previousTotals: previous,
            daily: daily ?? (9...15).map {
                RecapDayDTO(date: "2026-10-\(String(format: "%02d", $0))", captures: $0 % 3, learned: $0 % 2, asked: 1, reviewed: 0)
            },
            kinds: kinds,
            highlights: highlights,
            shareText: shareText
        )
    }
}
