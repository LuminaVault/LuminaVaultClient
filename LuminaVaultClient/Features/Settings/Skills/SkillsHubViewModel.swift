// LuminaVaultClient/LuminaVaultClient/Features/Settings/Skills/SkillsHubViewModel.swift
//
// HER-247 — Settings → Skills hub: drives the grouped list (Built-in /
// Custom / Disabled) of every skill the tenant has access to.

import Foundation
import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class SkillsHubViewModel {
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
            skills = response.skills
            state = .loaded
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    func toggle(skill: LuminaVaultShared.SkillDTO, enabled: Bool) async {
        do {
            let updated = try await client.patch(
                name: skill.name,
                body: SkillPatchRequest(enabled: enabled)
            )
            replace(updated)
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    func replace(_ updated: LuminaVaultShared.SkillDTO) {
        if let index = skills.firstIndex(where: { $0.id == updated.id }) {
            skills[index] = updated
        }
    }

    var builtInEnabled: [LuminaVaultShared.SkillDTO] {
        skills.filter { $0.source == .builtin && $0.enabled }
    }
    var customEnabled: [LuminaVaultShared.SkillDTO] {
        skills.filter { $0.source == .vault && $0.enabled }
    }
    var disabled: [LuminaVaultShared.SkillDTO] {
        skills.filter { !$0.enabled }
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized: return "Session expired — sign in again."
            case .networkFailure: return "Network unavailable."
            default: return "Couldn't load skills."
            }
        }
        return "Couldn't load skills."
    }
}
