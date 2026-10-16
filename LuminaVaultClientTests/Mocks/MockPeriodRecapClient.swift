// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockPeriodRecapClient.swift
//
// Scripted `PeriodRecapClientProtocol`: answers each call with the next
// queued result, and records what was asked.

@testable import LuminaVaultClient
import Foundation
import LuminaVaultShared

final class MockPeriodRecapClient: PeriodRecapClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Result<PeriodRecapResponse, Error>]
    private var _requests: [PeriodRecapRequest] = []

    init(_ results: [Result<PeriodRecapResponse, Error>]) {
        queue = results
    }

    var requests: [PeriodRecapRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    func periodRecap(_ request: PeriodRecapRequest) async throws -> PeriodRecapResponse {
        let next: Result<PeriodRecapResponse, Error>? = {
            lock.lock(); defer { lock.unlock() }
            _requests.append(request)
            return queue.isEmpty ? nil : queue.removeFirst()
        }()
        guard let next else { throw APIError.httpError(statusCode: 404, data: Data()) }
        return try next.get()
    }
}

extension PeriodRecapResponse {
    /// A finished March 2026 with every card, themes in `themes` state.
    static func fixture(
        period: RecapPeriodKind = .month,
        themes: RecapThemesStatus = .ready,
        available: Bool = true,
        reason: RecapUnavailableReason? = nil,
        order: [RecapCardKind]? = nil
    ) -> PeriodRecapResponse {
        let deck: [RecapCardKind] = order ?? [
            .intro, .captures, .peak, .rhythm, .topics, .chats, .skills, .streak, .achievements, .themes, .summary,
        ]
        var hours = Array(repeating: 0, count: 24)
        hours[22] = 9
        hours[9] = 3
        return PeriodRecapResponse(
            period: period,
            year: 2026,
            month: period == .month ? 3 : nil,
            start: "2026-03-01",
            end: "2026-03-31",
            timezone: "Europe/Lisbon",
            isComplete: true,
            available: available,
            unavailableReason: reason,
            order: available ? deck : [],
            captures: available ? RecapCapturesCardDTO(
                captures: 40,
                learned: 12,
                previousCaptures: 30,
                previousLearned: 10,
                series: (1 ... 31).map { RecapBucketDTO(key: String(format: "2026-03-%02d", $0), count: $0 % 5) }
            ) : nil,
            peak: available ? RecapPeakCardDTO(
                busiest: RecapBucketDTO(key: "2026-03-14", count: 9),
                weekdayCounts: [4, 6, 2, 8, 3, 9, 1],
                busiestWeekday: 6
            ) : nil,
            rhythm: available ? RecapRhythmCardDTO(hourCounts: hours, peakHour: 22, persona: .nightOwl) : nil,
            topics: available ? RecapTopicsCardDTO(
                topTags: [RecapCountDTO(label: "swift", count: 14), RecapCountDTO(label: "side_project", count: 6)],
                topSpace: RecapCountDTO(label: "Work", count: 20)
            ) : nil,
            chats: available ? RecapChatsCardDTO(conversations: 5, messagesSent: 30, previousMessagesSent: 20) : nil,
            skills: available ? RecapSkillsCardDTO(runs: 8, topSkill: RecapCountDTO(label: "daily-brief", count: 6)) : nil,
            streak: available ? RecapStreakCardDTO(
                longestDays: 6,
                longestStart: "2026-03-10",
                longestEnd: "2026-03-15",
                activeDays: 18,
                totalDays: 31
            ) : nil,
            achievements: available ? RecapAchievementsCardDTO(
                unlocked: 1,
                items: [RecapAchievementDTO(key: "k", title: "First week", unlockedAt: Date(timeIntervalSince1970: 1_773_000_000))]
            ) : nil,
            themes: available ? RecapThemesCardDTO(
                status: themes,
                headline: themes == .ready ? "Night owl builder" : nil,
                sentence: themes == .ready ? "You spent March building after dark." : nil,
                themes: themes == .ready ? ["swift", "shipping"] : [],
                fallbackSentence: "A month of swift and side_project."
            ) : nil,
            shareText: "My March 2026 on LuminaVault: 52 memories.",
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000)
        )
    }
}
