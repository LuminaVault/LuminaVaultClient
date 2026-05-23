// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Conversion/Models/ConversionFunnelChoices.swift
//
// HER-287 — typed option enums for the conversion onboarding funnel.
// Source-of-truth strings live here so a single change updates copy,
// analytics tags, and persisted answers in lockstep.

import Foundation

// MARK: - Screen 2: GOAL

enum FunnelGoal: String, CaseIterable, Identifiable, Sendable, Codable {
    case rememberReading
    case captureIdeas
    case healthInsights
    case knowledgeBase
    case patternTracking
    case justCurious

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .rememberReading: "🧠"
        case .captureIdeas:    "💭"
        case .healthInsights:  "🩺"
        case .knowledgeBase:   "📚"
        case .patternTracking: "🎯"
        case .justCurious:     "✨"
        }
    }

    var label: String {
        switch self {
        case .rememberReading: "Remember everything I read"
        case .captureIdeas:    "Capture ideas before they slip away"
        case .healthInsights:  "Make sense of my Health data"
        case .knowledgeBase:   "Build a personal knowledge base"
        case .patternTracking: "Track patterns in what I think + feel"
        case .justCurious:     "Just curious — show me what you do"
        }
    }
}

// MARK: - Screen 3: PAIN POINTS

enum FunnelPainPoint: String, CaseIterable, Identifiable, Sendable, Codable {
    case reExplainingContext
    case scatteredNotes
    case genericReplies
    case forgetWhatLearned
    case cloudPrivacy
    case lostInsights

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .reExplainingContext: "😩"
        case .scatteredNotes:      "📑"
        case .genericReplies:      "🤖"
        case .forgetWhatLearned:   "🔁"
        case .cloudPrivacy:        "🔒"
        case .lostInsights:        "💡"
        }
    }

    var label: String {
        switch self {
        case .reExplainingContext: "I waste time re-explaining context to ChatGPT"
        case .scatteredNotes:      "My notes live in 5 different apps"
        case .genericReplies:      "AI replies feel generic — they don't sound like me"
        case .forgetWhatLearned:   "I forget what I already learned about a topic"
        case .cloudPrivacy:        "I don't trust cloud AI with my private notes"
        case .lostInsights:        "I save insights I never look at again"
        }
    }
}

// MARK: - Screen 5: SWIPE CARD STATEMENTS

struct FunnelSwipeCard: Identifiable, Sendable, Equatable {
    let id: Int
    let statement: String

    static let all: [FunnelSwipeCard] = [
        .init(id: 0, statement: "I've answered the same prompt 3 different ways because ChatGPT keeps forgetting."),
        .init(id: 1, statement: "I screenshot articles I'll never read again."),
        .init(id: 2, statement: "I want AI that sounds like me, not a customer-service bot."),
        .init(id: 3, statement: "My notes app has hundreds of entries. None of them surface when I need them."),
    ]
}

// MARK: - Screen 8: CAPTURE SOURCES

enum FunnelCaptureSource: String, CaseIterable, Identifiable, Sendable, Codable {
    case safariArticles
    case photos
    case voiceMemos
    case healthData
    case hermesGateways
    case manualNotes

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .safariArticles:  "🌐"
        case .photos:          "📸"
        case .voiceMemos:      "🎤"
        case .healthData:      "❤️"
        case .hermesGateways:  "💬"
        case .manualNotes:     "📝"
        }
    }

    var label: String {
        switch self {
        case .safariArticles:  "Articles + links (Safari Share)"
        case .photos:          "Photos + screenshots"
        case .voiceMemos:      "Voice memos"
        case .healthData:      "Health data (workouts, sleep)"
        case .hermesGateways:  "Telegram / Slack (via Hermes)"
        case .manualNotes:     "Manual notes + memos"
        }
    }
}
