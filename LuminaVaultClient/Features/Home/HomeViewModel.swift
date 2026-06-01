// LuminaVaultClient/LuminaVaultClient/Features/Home/HomeViewModel.swift
//
// HER-244 — drives the OS Shell Home/Dashboard. Loads stats + tasks +
// insights + reachability in parallel; surfaces each card's load state
// independently so a single endpoint failure does not blank the screen.

import Foundation
import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class HomeViewModel {
    enum CardState<T: Sendable>: Sendable {
        case loading
        case loaded(T)
        case failed(message: String)

        var value: T? {
            if case .loaded(let v) = self { return v }
            return nil
        }
    }

    // Card-level state. Each settles independently from `refresh()`.
    var stats: CardState<DashboardStatsResponse> = .loading
    var profile: CardState<DashboardProfileResponse> = .loading
    var tasks: CardState<[TaskDTO]> = .loading
    var insights: CardState<[InsightDTO]> = .loading
    // HER-Home — one-shot dashboard counts (skills, jobs, reminders, todos,
    // projects, insights) + active profile, and month-to-date usage.
    var home: CardState<HomeSummaryResponse> = .loading
    var usage: CardState<UsageSummaryResponse> = .loading
    var isOnline: Bool = true

    // Inherited from the existing kb-compile flow (HER-36 / HER-39). The
    // dashboard's "Trigger Compile" big-button delegates here so the
    // offline-queueing and mascot-state behaviour is preserved verbatim.
    let compileViewModel: SyncAndLearnViewModel

    // Greeting copy reads from AppState.currentEmail; SOUL.md-personalised
    // greeting (HER-250) is out of scope for HER-244.
    let displayName: String

    private let statsClient: DashboardStatsClientProtocol
    private let profileClient: DashboardProfileClientProtocol
    private let tasksClient: TasksClientProtocol
    private let insightsClient: InsightsClientProtocol
    private let healthClient: HealthClientProtocol
    // HER-Home — optional so existing call sites keep compiling; when nil the
    // corresponding card simply stays in its initial state.
    private let homeClient: HomeSummaryClientProtocol?
    private let analyticsClient: AnalyticsClientProtocol?

    init(
        statsClient: DashboardStatsClientProtocol,
        profileClient: DashboardProfileClientProtocol,
        tasksClient: TasksClientProtocol,
        insightsClient: InsightsClientProtocol,
        healthClient: HealthClientProtocol,
        compileViewModel: SyncAndLearnViewModel,
        displayName: String,
        homeClient: HomeSummaryClientProtocol? = nil,
        analyticsClient: AnalyticsClientProtocol? = nil
    ) {
        self.statsClient = statsClient
        self.profileClient = profileClient
        self.tasksClient = tasksClient
        self.insightsClient = insightsClient
        self.healthClient = healthClient
        self.compileViewModel = compileViewModel
        self.displayName = displayName
        self.homeClient = homeClient
        self.analyticsClient = analyticsClient
    }

    func refresh() async {
        stats = .loading
        profile = .loading
        tasks = .loading
        insights = .loading

        async let statsTask: Void = loadStats()
        async let profileTask: Void = loadProfile()
        async let tasksTask: Void = loadTasks()
        async let insightsTask: Void = loadInsights()
        async let healthTask: Void = checkHealth()
        async let homeTask: Void = loadHome()
        async let usageTask: Void = loadUsage()
        _ = await (statsTask, profileTask, tasksTask, insightsTask, healthTask, homeTask, usageTask)
    }

    private func loadHome() async {
        guard let homeClient else { return }
        do {
            home = .loaded(try await homeClient.summary())
        } catch {
            home = .failed(message: friendlyMessage(error))
        }
    }

    private func loadUsage() async {
        guard let analyticsClient else { return }
        do {
            usage = .loaded(try await analyticsClient.usageSummary())
        } catch {
            usage = .failed(message: friendlyMessage(error))
        }
    }

    func triggerCompile() async {
        await compileViewModel.sync()
        // Stats reflect last-compile timestamp — refresh just that card.
        await loadStats()
    }

    private func loadStats() async {
        do {
            let result = try await statsClient.stats()
            stats = .loaded(result)
        } catch {
            stats = .failed(message: friendlyMessage(error))
        }
    }

    private func loadProfile() async {
        do {
            let result = try await profileClient.profile()
            profile = .loaded(result)
        } catch {
            profile = .failed(message: friendlyMessage(error))
        }
    }

    private func loadTasks() async {
        do {
            let result = try await tasksClient.list(state: nil, limit: 5)
            tasks = .loaded(result.tasks)
        } catch {
            tasks = .failed(message: friendlyMessage(error))
        }
    }

    private func loadInsights() async {
        do {
            let result = try await insightsClient.list(section: nil, limit: 3)
            insights = .loaded(result.insights)
        } catch {
            insights = .failed(message: friendlyMessage(error))
        }
    }

    private func checkHealth() async {
        isOnline = await healthClient.isOnline()
    }

    private func friendlyMessage(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized: return "Session expired — sign in again."
            case .networkFailure: return "Network unavailable."
            default: return "Couldn't load."
            }
        }
        return "Couldn't load."
    }
}
