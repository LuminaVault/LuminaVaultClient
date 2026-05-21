// LuminaVaultClient/LuminaVaultClient/Features/Settings/Skills/SkillDetailViewModel.swift
//
// HER-247 — skill detail screen: full description, cadence, channel,
// sparkline, recent runs list.

import Foundation
import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class SkillDetailViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var skill: LuminaVaultShared.SkillDTO
    var runsState: LoadState = .loading
    var runs: [SkillRunDTO] = []
    var sparkline: [SkillSparklinePoint] = []

    private let client: SkillsClientProtocol
    var onSkillUpdated: ((LuminaVaultShared.SkillDTO) -> Void)?

    init(skill: LuminaVaultShared.SkillDTO, client: SkillsClientProtocol) {
        self.skill = skill
        self.client = client
    }

    func loadRuns() async {
        runsState = .loading
        do {
            let response = try await client.runs(name: skill.name, limit: 50)
            runs = response.runs
            sparkline = response.sparkline
            runsState = .loaded
        } catch {
            runsState = .failed(Self.message(for: error))
        }
    }

    func toggle(enabled: Bool) async {
        await patch(body: SkillPatchRequest(enabled: enabled))
    }

    func setCadence(_ cron: String) async {
        // Empty string clears the override on the server.
        await patch(body: SkillPatchRequest(scheduleOverride: cron))
    }

    func setChannel(_ category: APNSCategory) async {
        await patch(body: SkillPatchRequest(apnsCategory: category))
    }

    private func patch(body: SkillPatchRequest) async {
        do {
            let updated = try await client.patch(name: skill.name, body: body)
            skill = updated
            onSkillUpdated?(updated)
        } catch {
            runsState = .failed(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized: return "Session expired — sign in again."
            case .networkFailure: return "Network unavailable."
            default: return "Couldn't load skill detail."
            }
        }
        return "Couldn't load skill detail."
    }
}
