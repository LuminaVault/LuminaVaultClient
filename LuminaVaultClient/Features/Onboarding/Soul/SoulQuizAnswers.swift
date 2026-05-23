// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Soul/SoulQuizAnswers.swift
//
// HER-100 — value type holding every answer the user gives during the
// 5-step SOUL.md onboarding quiz. Kept `Codable` so the in-progress
// state can round-trip through `UserDefaults` for resume-on-relaunch.

import Foundation

enum SoulTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case formal, casual, playful, dry, warm
    var id: String { rawValue }

    var label: String {
        switch self {
        case .formal: "Formal"
        case .casual: "Casual"
        case .playful: "Playful"
        case .dry: "Dry"
        case .warm: "Warm"
        }
    }
}

/// HER-100 step 2 — multi-select priorities the user wants Hermes to
/// focus on. `other` is paired with a free-text payload captured on
/// the same screen so a unique priority can be added without bloating
/// the chip grid.
enum SoulPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case focus, health, learning, family, money, creative, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .focus: "Focus"
        case .health: "Health"
        case .learning: "Learning"
        case .family: "Family"
        case .money: "Money"
        case .creative: "Creative"
        case .other: "Other"
        }
    }
}

enum SoulFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case bullets, prose
    var id: String { rawValue }
    var label: String { self == .bullets ? "Bullet points" : "Prose" }
}

enum SoulLength: String, Codable, CaseIterable, Identifiable, Sendable {
    case short, long
    var id: String { rawValue }
    var label: String { self == .short ? "Short" : "Long" }
}

/// HER-100 — full snapshot of quiz progress + answers. Persisted in
/// `UserDefaults` under a per-user key so killing the app on step 3
/// resumes on step 3 with the chosen tone and priorities intact.
struct SoulQuizAnswers: Codable, Equatable, Sendable {
    var tone: SoulTone?
    var priorities: Set<SoulPriority> = []
    var otherPriority: String = ""
    var format: SoulFormat = .bullets
    var length: SoulLength = .short
    var emojis: Bool = false
    var voiceSamples: [String] = []
    /// Markdown the user can hand-edit on the confirm step before saving.
    /// `nil` until the confirm step renders the generated draft for the
    /// first time; subsequent screens treat a non-nil value as the
    /// user's authoritative override of the generated default.
    var editedMarkdown: String?
}
