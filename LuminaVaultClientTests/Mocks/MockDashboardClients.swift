// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockDashboardClients.swift
// HER-244 — scripted fakes for the four HTTP clients HomeViewModel
// depends on: stats, tasks, insights, health.

@testable import LuminaVaultClient
import Foundation
import LuminaVaultShared

final class MockDashboardStatsClient: DashboardStatsClientProtocol, @unchecked Sendable {
    var result: Result<DashboardStatsResponse, Error> = .success(.empty)
    private(set) var callCount = 0

    func stats() async throws -> DashboardStatsResponse {
        callCount += 1
        return try result.get()
    }
}

final class MockDashboardProfileClient: DashboardProfileClientProtocol, @unchecked Sendable {
    var result: Result<DashboardProfileResponse, Error> = .success(.empty)
    private(set) var callCount = 0

    func profile() async throws -> DashboardProfileResponse {
        callCount += 1
        return try result.get()
    }
}

final class MockTasksClient: TasksClientProtocol, @unchecked Sendable {
    var result: Result<TaskListResponse, Error> = .success(TaskListResponse(tasks: []))
    private(set) var callCount = 0
    private(set) var lastState: TaskState?
    private(set) var lastLimit: Int?

    func list(state: TaskState?, limit: Int?) async throws -> TaskListResponse {
        callCount += 1
        lastState = state
        lastLimit = limit
        return try result.get()
    }
}

final class MockInsightsClient: InsightsClientProtocol, @unchecked Sendable {
    var result: Result<InsightListResponse, Error> = .success(InsightListResponse(insights: []))
    private(set) var callCount = 0
    private(set) var lastSection: InsightSection?
    private(set) var lastLimit: Int?

    func list(section: InsightSection?, limit: Int?) async throws -> InsightListResponse {
        callCount += 1
        lastSection = section
        lastLimit = limit
        return try result.get()
    }
}

final class MockHealthClient: HealthClientProtocol, @unchecked Sendable {
    var online = true
    private(set) var callCount = 0

    func isOnline() async -> Bool {
        callCount += 1
        return online
    }
}

extension DashboardStatsResponse {
    static let empty = DashboardStatsResponse(memoriesToday: 0, memoriesTotal: 0, lastCompileAt: nil)

    static func stub(today: Int = 5, total: Int = 42, lastCompileAt: Date? = nil) -> DashboardStatsResponse {
        DashboardStatsResponse(memoriesToday: today, memoriesTotal: total, lastCompileAt: lastCompileAt)
    }
}

extension DashboardProfileResponse {
    static let empty = DashboardProfileResponse(
        skillsCount: 0, jobsCount: 0, sessionsCount: 0,
        badgesEarned: 0, powerLevel: 1, powerXP: 0
    )

    static func stub(
        skills: Int = 6, jobs: Int = 18, sessions: Int = 9,
        badges: Int = 4, powerLevel: Int = 8, powerXP: Int = 63
    ) -> DashboardProfileResponse {
        DashboardProfileResponse(
            skillsCount: skills, jobsCount: jobs, sessionsCount: sessions,
            badgesEarned: badges, powerLevel: powerLevel, powerXP: powerXP
        )
    }
}

extension TaskDTO {
    static func stub(
        label: String = "Compile vault",
        state: TaskState = .running,
        progress: Double? = 0.42
    ) -> TaskDTO {
        TaskDTO(
            id: UUID(),
            kind: "kb-compile",
            label: label,
            state: state,
            progress: progress,
            startedAt: Date(timeIntervalSince1970: 0),
            elapsedSeconds: 12,
            error: nil
        )
    }
}

extension InsightDTO {
    static func stub(
        headline: String = "Headline",
        section: InsightSection = .thisWeek
    ) -> InsightDTO {
        InsightDTO(
            id: UUID(),
            headline: headline,
            summary: "A short narrative summary of the finding.",
            section: section,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}
