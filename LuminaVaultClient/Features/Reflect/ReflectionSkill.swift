// LuminaVaultClient/LuminaVaultClient/Features/Reflect/ReflectionSkill.swift
//
// HER-194 — three Reflect cards. `serverName` is the path segment the
// server registers each synth-cluster skill under (`/v1/skills/{name}/run`).

import Foundation

enum ReflectionSkill: String, Identifiable, CaseIterable, Sendable {
    case patterns
    case contradictions
    case beliefs

    var id: String { rawValue }
    var serverName: String { rawValue }

    var title: String {
        switch self {
        case .patterns: "Patterns"
        case .contradictions: "Contradictions"
        case .beliefs: "Beliefs"
        }
    }

    var subtitle: String {
        switch self {
        case .patterns: "Find themes across your notes"
        case .contradictions: "Spot clashing ideas"
        case .beliefs: "Trace stance evolution"
        }
    }

    var iconSystemName: String {
        switch self {
        case .patterns: "rectangle.stack.fill"
        case .contradictions: "arrow.triangle.2.circlepath"
        case .beliefs: "scroll.fill"
        }
    }

    /// Beliefs needs a topic to anchor the stance-evolution trace; the
    /// other two can run open-ended over the whole vault.
    var topicRequired: Bool { self == .beliefs }

    var inputPlaceholder: String {
        switch self {
        case .patterns: "Optional: focus area (e.g. \"productivity\")"
        case .contradictions: "Optional: domain (e.g. \"javascript frameworks\")"
        case .beliefs: "Required: topic (e.g. \"remote work\")"
        }
    }
}
