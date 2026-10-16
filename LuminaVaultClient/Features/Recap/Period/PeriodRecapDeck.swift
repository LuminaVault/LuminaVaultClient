// LuminaVaultClient/LuminaVaultClient/Features/Recap/Period/PeriodRecapDeck.swift
//
// The year / month in review's words around the numbers: which cards play,
// how long each lasts, and how a bucket, persona or delta reads. Pure, so
// the rules are tested without a view.

import Foundation
import LuminaVaultShared

nonisolated enum PeriodRecapDeck {
    static let cardSeconds: Double = 5
    static let themesSeconds: Double = 7

    static func duration(of kind: RecapCardKind) -> Double {
        kind == .themes ? themesSeconds : cardSeconds
    }

    /// The server's `order`, minus kinds this build does not know and kinds
    /// whose card is missing. Intro and summary have no payload of their own.
    static func cards(for recap: PeriodRecapResponse) -> [RecapCardKind] {
        guard recap.available else { return [] }
        return recap.order.filter { kind in
            switch kind {
            case .intro, .summary: true
            case .captures: recap.captures != nil
            case .peak: recap.peak != nil
            case .rhythm: recap.rhythm != nil
            case .topics: recap.topics != nil
            case .chats: recap.chats != nil
            case .skills: recap.skills != nil
            case .streak: recap.streak != nil
            case .achievements: recap.achievements != nil
            case .themes: recap.themes != nil
            case .unknown: false
            }
        }
    }

    static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    static let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// "2026" or "March 2026".
    static func periodName(period: RecapPeriodKind, year: Int, month: Int?) -> String {
        guard period == .month, let month, (1 ... 12).contains(month) else { return String(year) }
        return "\(monthNames[month - 1]) \(year)"
    }

    static func periodName(_ recap: PeriodRecapResponse) -> String {
        periodName(period: recap.period, year: recap.year, month: recap.month)
    }

    /// "2026-03" → "March", "2026-03-14" → "14 March".
    static func bucketName(_ key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 2, (1 ... 12).contains(parts[1]) else { return key }
        let month = monthNames[parts[1] - 1]
        return parts.count >= 3 ? "\(parts[2]) \(month)" : month
    }

    static func weekdayName(_ isoWeekday: Int) -> String {
        (1 ... 7).contains(isoWeekday) ? weekdayNames[isoWeekday - 1] : ""
    }

    static func persona(_ persona: RecapPersona?) -> (title: String, line: String) {
        switch persona {
        case .earlyBird: ("Early bird", "Your best thinking happened before 10am.")
        case .daytime: ("Daytime thinker", "You did your best work in daylight.")
        case .evening: ("Evening thinker", "Your ideas came alive after work.")
        case .nightOwl: ("Night owl", "Your best ideas showed up after dark.")
        case .balanced, .unknown, nil: ("All-day thinker", "You showed up whenever an idea did.")
        }
    }

    /// "+40%", "−12%", "Same as before", or nil with nothing to compare.
    static func delta(_ current: Int, previous: Int) -> String? {
        guard previous > 0 else { return nil }
        let change = Int((Double(current - previous) / Double(previous) * 100).rounded())
        if change == 0 { return "Same as before" }
        return change > 0 ? "+\(change)%" : "\u{2212}\(abs(change))%"
    }

    /// "8am", "12pm", "11pm".
    static func hourLabel(_ hour: Int) -> String {
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelve)\(hour < 12 ? "am" : "pm")"
    }

    /// Heights 0…1, so the tallest bar fills the card.
    static func normalised(_ values: [Int]) -> [Double] {
        let top = values.max() ?? 0
        return values.map { top == 0 ? 0 : Double($0) / Double(top) }
    }

    static func memories(_ recap: PeriodRecapResponse) -> Int {
        (recap.captures?.captures ?? 0) + (recap.captures?.learned ?? 0)
    }

    /// The model's sentence when written, else the counted one.
    static func themes(_ recap: PeriodRecapResponse) -> (headline: String?, sentence: String) {
        guard let themes = recap.themes else { return (nil, "") }
        if themes.status == .ready, let sentence = themes.sentence {
            return (themes.headline, sentence)
        }
        return (nil, themes.fallbackSentence)
    }

    static func unavailableText(_ recap: PeriodRecapResponse) -> String {
        let span = recap.period == .month ? "month" : "year"
        switch recap.unavailableReason {
        case .periodInFuture: return "That \(span) hasn't started yet."
        case .beforeAccount: return "That \(span) ended before you joined Lumina."
        default: return "Not enough happened this \(span) for a recap yet. Save a few more memories and check back."
        }
    }

    /// The share card's numbers. Never a tag, title, Space name or theme.
    static func shareStats(_ recap: PeriodRecapResponse) -> [(value: String, label: String)] {
        var stats = [(value: memories(recap).formatted(), label: "memories")]
        if let chats = recap.chats, chats.messagesSent > 0 {
            stats.append((chats.messagesSent.formatted(), "questions asked"))
        }
        if let streak = recap.streak, streak.longestDays > 0 {
            stats.append(("\(streak.longestDays)", "day streak"))
            stats.append((streak.activeDays.formatted(), "active days"))
        }
        if let skills = recap.skills, skills.runs > 0 {
            stats.append((skills.runs.formatted(), "agent runs"))
        }
        if let achievements = recap.achievements, achievements.unlocked > 0 {
            stats.append(("\(achievements.unlocked)", "badges"))
        }
        return Array(stats.prefix(6))
    }
}
