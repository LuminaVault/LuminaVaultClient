// LuminaVaultClient/LuminaVaultClient/Features/Reflect/ReflectionRunner.swift
//
// HER-194 — drives one reflection through the skill-run pipeline and
// caches the rendered markdown so Save uploads it directly to the vault
// without firing a second LLM call.

import Foundation
import LuminaVaultShared
import SwiftUI

enum ReflectionError: Error, Equatable {
    case rateLimited
    case network(String)
    case validation(String)

    var userMessage: String {
        switch self {
        case .rateLimited:
            return "You've used your 3 reflections today. Resets at midnight."
        case .network(let message), .validation(let message):
            return message
        }
    }
}

@Observable
@MainActor
final class ReflectionRunner {
    enum State {
        case idle
        case running
        case result(SkillRunResponse)
        case saving(SkillRunResponse)
        case saved(SkillRunResponse, savedPath: String)
        case failed(ReflectionError)
    }

    var state: State = .idle

    private let skillsClient: SkillsClientProtocol
    private let vaultUploadClient: VaultUploadClientProtocol

    init(
        skillsClient: SkillsClientProtocol,
        vaultUploadClient: VaultUploadClientProtocol,
    ) {
        self.skillsClient = skillsClient
        self.vaultUploadClient = vaultUploadClient
    }

    func run(skill: ReflectionSkill, topic: String?) async {
        let trimmed = topic?.trimmingCharacters(in: .whitespacesAndNewlines)
        if skill.topicRequired, (trimmed?.isEmpty ?? true) {
            state = .failed(.validation("Topic is required for \(skill.title)."))
            return
        }
        state = .running
        let request = SkillRunRequest(
            input: (trimmed?.isEmpty == false) ? trimmed : nil,
            arguments: nil,
            save: false,
        )
        do {
            let response = try await skillsClient.run(name: skill.serverName, request: request)
            state = .result(response)
        } catch APIError.rateLimited {
            state = .failed(.rateLimited)
        } catch {
            state = .failed(.network(Self.message(for: error)))
        }
    }

    func save(skill: ReflectionSkill, topic: String?, response: SkillRunResponse) async {
        state = .saving(response)
        let path = Self.savePath(skill: skill, topic: topic)
        let data = Data(response.markdown.utf8)
        do {
            let uploaded = try await vaultUploadClient.uploadAsset(
                data: data,
                contentType: "text/markdown",
                relativePath: path,
                spaceID: nil,
            )
            state = .saved(response, savedPath: uploaded.path)
        } catch APIError.rateLimited {
            state = .failed(.rateLimited)
        } catch {
            state = .failed(.network(Self.message(for: error)))
        }
    }

    func reset() {
        state = .idle
    }

    // MARK: - Helpers (exposed for tests)

    static func savePath(skill: ReflectionSkill, topic: String?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let date = formatter.string(from: Date())
        let slug = slugify(topic ?? "untitled")
        return "reflections/\(date)/\(skill.serverName)-\(slug).md"
    }

    static func slugify(_ raw: String) -> String {
        let lower = raw.lowercased()
        let latin = lower.applyingTransform(.toLatin, reverse: false) ?? lower
        let stripped = latin.applyingTransform(.stripCombiningMarks, reverse: false) ?? latin
        var slug = ""
        var lastWasDash = false
        for ch in stripped {
            if ch.isLetter || ch.isNumber {
                slug.append(ch)
                lastWasDash = false
            } else if !lastWasDash, !slug.isEmpty {
                slug.append("-")
                lastWasDash = true
            }
        }
        if slug.hasSuffix("-") { slug.removeLast() }
        if slug.isEmpty { return "untitled" }
        return String(slug.prefix(40))
    }

    private static func message(for error: Error) -> String {
        if let api = error as? APIError {
            return api.errorDescription ?? "Reflection failed."
        }
        return error.localizedDescription
    }
}
