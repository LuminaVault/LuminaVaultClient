// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Soul/SoulQuizAnswers.swift
//
// HER-100 — value type holding every answer the user gives during the
// 5-step SOUL.md onboarding quiz. Kept `Codable` so the in-progress
// state can round-trip through `UserDefaults` for resume-on-relaunch.
//
// Template v2: the enums are the shared wire types (`LuminaVaultShared`)
// because the quiz now posts them to `POST /v1/soul/compose`. Raw values
// are identical to the old client-local enums, so persisted quiz state
// keeps decoding. UI-only affordances (labels, Identifiable) live in the
// extensions below — LuminaVaultShared stays presentation-free.

import Foundation
import LuminaVaultShared

extension SoulTone: @retroactive Identifiable {
    public var id: String { rawValue }

    /// The curated tones offered on the quiz chip grid. The shared enum
    /// also carries the server-composer tones (`conciseTechnical`, `coach`)
    /// which the quiz doesn't surface.
    static var quizCases: [SoulTone] { [.formal, .casual, .playful, .dry, .warm] }

    var label: String {
        switch self {
        case .formal: "Formal"
        case .casual: "Casual"
        case .playful: "Playful"
        case .dry: "Dry"
        case .warm: "Warm"
        case .conciseTechnical: "Concise technical"
        case .coach: "Coach"
        }
    }
}

extension SoulPriority: @retroactive Identifiable {
    public var id: String { rawValue }

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

extension SoulFormat: @retroactive Identifiable {
    public var id: String { rawValue }
    var label: String { self == .bullets ? "Bullet points" : "Prose" }
}

extension SoulLength: @retroactive Identifiable {
    public var id: String { rawValue }
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

extension SoulComposeRequest {
    /// Maps the quiz snapshot onto the compose wire request. Stable
    /// priority order (declaration order) so the composed draft doesn't
    /// reflow between renders of the same answers.
    init(from answers: SoulQuizAnswers, dryRun: Bool) {
        self.init(
            agentName: nil,
            tone: answers.tone,
            role: nil,
            autonomy: nil,
            priorities: SoulPriority.allCases.filter { answers.priorities.contains($0) },
            otherPriority: answers.otherPriority.trimmingCharacters(in: .whitespacesAndNewlines),
            format: answers.format,
            length: answers.length,
            emojis: answers.emojis,
            voiceSamples: answers.voiceSamples,
            dryRun: dryRun
        )
    }
}
