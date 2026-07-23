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
    var curatorResource: LVImprovementResource?

    private let client: SkillsClientProtocol
    private let improvementClient: (any SelfImprovementClientProtocol)?
    var onSkillUpdated: ((LuminaVaultShared.SkillDTO) -> Void)?

    init(
        skill: LuminaVaultShared.SkillDTO,
        client: SkillsClientProtocol,
        improvementClient: (any SelfImprovementClientProtocol)? = nil
    ) {
        self.skill = skill
        self.client = client
        self.improvementClient = improvementClient
    }

    func loadRuns() async {
        runsState = .loading
        do {
            let response = try await client.runs(name: skill.name, limit: 50)
            runs = response.runs
            sparkline = response.sparkline
            if let improvementClient {
                curatorResource = try await improvementClient.resources().first {
                    $0.kind == .skill && $0.name == skill.name
                }
            }
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

    func setPinned(_ pinned: Bool) async {
        guard let resource = curatorResource, let improvementClient else { return }
        do { curatorResource = try await improvementClient.pin(resource, pinned: pinned) }
        catch { runsState = .failed(Self.message(for: error)) }
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
