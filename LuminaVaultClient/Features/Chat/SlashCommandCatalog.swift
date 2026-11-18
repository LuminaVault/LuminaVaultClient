// LuminaVaultClient/LuminaVaultClient/Features/Chat/SlashCommandCatalog.swift
//
// Chat slash commands: what the composer suggests while the draft is a bare
// `/word`. The server (`POST /v1/skills/slash`) is the parser; this only
// lists what it understands — its built-ins plus the user's enabled skills.

import Foundation
import LuminaVaultShared

/// One row in the composer's slash suggestion list.
struct SlashSuggestion: Identifiable, Equatable, Sendable {
    /// The command without the slash, e.g. `kb-compile`.
    let name: String
    let summary: String
    /// Shown after the name when the command expects text, e.g. `<topic>`.
    let argumentHint: String?

    var id: String {
        name
    }

    /// What a tap puts in the composer: the command and a trailing space so
    /// the user can type the argument straight away.
    var insertion: String {
        "/\(name) "
    }
}

enum SlashCommandCatalog {
    /// The commands `skills.ParseSlash` handles itself, before any skill
    /// lookup. Kept in the server's order.
    static let builtIns: [SlashSuggestion] = [
        SlashSuggestion(
            name: "kb-compile",
            summary: "Compile new captures into your knowledge base",
            argumentHint: nil
        ),
        SlashSuggestion(name: "patterns", summary: "Find recurring patterns in your notes", argumentHint: "<topic>"),
        SlashSuggestion(name: "contradict", summary: "Look for contradictions in your notes", argumentHint: "<topic>"),
        SlashSuggestion(name: "beliefs", summary: "Trace how a belief changed over time", argumentHint: "<topic>"),
    ]

    /// Skills the server runs under their own names. The built-in aliases
    /// already cover the detector skills, and Hermes skills run on Hermes,
    /// not through `/v1/skills/slash`.
    static func suggestions(from skills: [SkillDTO]) -> [SlashSuggestion] {
        let covered: Set = ["pattern-detector", "contradiction-detector", "belief-evolution", "kb-compile"]
        return skills
            .filter { $0.enabled && !covered.contains($0.name) && !$0.name.hasPrefix("hermes-") }
            .map { SlashSuggestion(name: $0.name, summary: $0.descriptionText, argumentHint: nil) }
    }

    /// The rows to show for `draft`. Only while the draft is a single
    /// `/word`: once the user types a space they are writing the argument.
    static func matches(for draft: String, in catalog: [SlashSuggestion]) -> [SlashSuggestion] {
        guard draft.hasPrefix("/"), !draft.contains(where: \.isWhitespace) else { return [] }
        let typed = draft.dropFirst().lowercased()
        var seen = Set<String>()
        return catalog.filter { suggestion in
            guard suggestion.name.hasPrefix(typed), seen.insert(suggestion.name).inserted else { return false }
            return true
        }
    }

    /// True when `text` should go to `/v1/skills/slash` rather than chat:
    /// a leading slash followed by a command word.
    static func isCommand(_ text: String) -> Bool {
        guard text.hasPrefix("/"), let first = text.dropFirst().first else { return false }
        return !first.isWhitespace && first != "/"
    }
}
