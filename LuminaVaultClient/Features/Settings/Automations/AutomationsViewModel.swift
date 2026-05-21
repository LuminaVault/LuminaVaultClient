// LuminaVaultClient/LuminaVaultClient/Features/Settings/Automations/AutomationsViewModel.swift
//
// HER-178 — Settings → Automations. Lighter-weight surface than the
// Skills hub: enable + cadence preset inline; full detail lives in
// the Skills hub (HER-247).

import Foundation
import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class AutomationsViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var state: LoadState = .loading
    var skills: [LuminaVaultShared.SkillDTO] = []

    private let client: SkillsClientProtocol

    init(client: SkillsClientProtocol) {
        self.client = client
    }

    func load() async {
        state = .loading
        do {
            let response = try await client.list()
            skills = response.skills.sorted { $0.name < $1.name }
            state = .loaded
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    func toggle(_ skill: LuminaVaultShared.SkillDTO, enabled: Bool) async {
        await patch(skill, body: SkillPatchRequest(enabled: enabled))
    }

    func setCadence(_ skill: LuminaVaultShared.SkillDTO, cron: String) async {
        await patch(skill, body: SkillPatchRequest(scheduleOverride: cron))
    }

    private func patch(_ skill: LuminaVaultShared.SkillDTO, body: SkillPatchRequest) async {
        do {
            let updated = try await client.patch(name: skill.name, body: body)
            if let index = skills.firstIndex(where: { $0.id == updated.id }) {
                skills[index] = updated
            }
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized: return "Session expired — sign in again."
            case .networkFailure: return "Network unavailable."
            default: return "Couldn't load automations."
            }
        }
        return "Couldn't load automations."
    }
}
