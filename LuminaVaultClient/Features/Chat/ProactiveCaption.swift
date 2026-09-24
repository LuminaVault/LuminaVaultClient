// LuminaVaultClient/LuminaVaultClient/Features/Chat/ProactiveCaption.swift
//
// Muse Stage C (`_reviews/muse-chat-contract.md`, "Proactive messages") — the
// 11pt uppercase line above an agent bubble Hermie sent on its own rather than
// in reply. The server tags those messages `origin: proactive` and names the
// sender in `sourceLabel`: a skill name ("daily-brief") or `job-<slug>` for a
// standing task. Pure so the mapping is testable without a view.

import Foundation
import LuminaVaultShared

nonisolated enum ProactiveCaption {
    /// `sourceLabel` of the morning briefing skill.
    static let briefingLabel = "daily-brief"
    /// Standing tasks (Lumina Jobs) are labelled `job-<slug>`.
    static let jobPrefix = "job-"

    /// Caption for a message, or nil when it needs none (every reply).
    ///
    /// - `daily-brief` → "Briefing · 07:00" (24-hour, in `timeZone`)
    /// - `job-*`       → "Standing task"
    /// - anything else → "From {Label}", the skill name made readable
    static func text(
        origin: ConversationMessageOrigin,
        sourceLabel: String?,
        createdAt: Date?,
        timeZone: TimeZone = .current
    ) -> String? {
        guard origin == .proactive else { return nil }
        let label = sourceLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if label == briefingLabel {
            guard let createdAt else { return "Briefing" }
            return "Briefing · \(clock(createdAt, timeZone: timeZone))"
        }
        if label.hasPrefix(jobPrefix) {
            return "Standing task"
        }
        // The thread these land in is Hermie's own; an unlabelled one is hers.
        return "From \(label.isEmpty ? "Hermie" : readable(label))"
    }

    /// "weekly-review" → "Weekly review". Separators become spaces and only
    /// the first letter is raised — the caption is uppercased on screen, so
    /// this is what VoiceOver reads, not what the eye sees.
    static func readable(_ label: String) -> String {
        let spaced = label
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        guard let first = spaced.first else { return label }
        return first.uppercased() + spaced.dropFirst()
    }

    /// "HH:mm" regardless of the device's 12/24-hour setting — the contract
    /// pins "Briefing · 07:00". A fixed POSIX format, not a template.
    private static func clock(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// Muse Stage C ("Standing-task card") — what Hermie says after a standing
/// task is created: "Got it — I'll watch X and ping you when Y".
///
/// The job proposal carries a title, a human schedule and an imperative spec,
/// not a separate "what" and "when". X is the title; Y is the spec's own
/// condition clause when it has one ("…; alert when 5 consecutive dry days"),
/// otherwise the schedule, so the sentence never promises a trigger the job
/// does not have.
nonisolated enum StandingTaskConfirmation {
    static func text(title: String?, spec: String?, scheduleHuman: String?) -> String {
        let subject = subject(title)
        if let condition = condition(in: spec) {
            return "Got it — I'll watch \(subject) and ping you when \(condition)."
        }
        if let schedule = trimmed(scheduleHuman) {
            return "Got it — I'll watch \(subject) and ping you \(lowercasedFirst(schedule))."
        }
        return "Got it — I'll watch \(subject) and ping you when there's something new."
    }

    /// The job's `sourceLabel` for the local confirmation — the same
    /// `job-<slug>` shape the server uses, so it maps to "Standing task".
    static func sourceLabel(title: String?) -> String {
        let slug = String((title ?? "").lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return ProactiveCaption.jobPrefix + (slug.isEmpty ? "job" : slug)
    }

    private static func subject(_ title: String?) -> String {
        guard let title = trimmed(title) else { return "this" }
        return lowercasedFirst(title)
    }

    /// The text after the spec's first "when"/"if" word, up to the end of
    /// that sentence. Nil when the spec states no condition.
    static func condition(in spec: String?) -> String? {
        guard let spec = trimmed(spec) else { return nil }
        let pattern = #"\b(?:when|whenever|if)\s+([^.;!?\n]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let ns = spec as NSString
        guard let match = regex.firstMatch(in: spec, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1
        else { return nil }
        return trimmed(ns.substring(with: match.range(at: 1)))
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        // A trailing full stop would double up with the sentence's own.
        return value.hasSuffix(".") ? String(value.dropLast()) : value
    }

    /// Lowers only a leading capital that starts an ordinary word, so
    /// "Weather" → "weather" but "AAPL price" and "iPhone" are left alone.
    private static func lowercasedFirst(_ value: String) -> String {
        let chars = Array(value)
        guard let first = chars.first, first.isUppercase else { return value }
        if chars.count > 1, chars[1].isUppercase { return value }
        return first.lowercased() + String(chars.dropFirst())
    }
}
