// LuminaVaultClient/LuminaVaultClient/Features/Commitments/CommitmentCopy.swift
//
// The words both commitment surfaces — the brief's Open loops card and the
// full list — use for a commitment's due date and for an answer that did not
// land.

import Foundation
import LuminaVaultShared

nonisolated enum CommitmentCopy {
    static let saveFailed = "Couldn't save that. Try again."
    /// PATCH 409: reopening would duplicate a commitment that is already
    /// open with the same text.
    static let alreadyOpen = "You already have an open loop that says the same thing, so this one stays closed."
    /// PATCH 404: gone on the server (deleted with its note, or another device).
    static let gone = "That one isn't there any more."

    static func failureMessage(for error: any Error) -> String {
        guard case let APIError.httpError(statusCode, _) = error else { return saveFailed }
        switch statusCode {
        case 409: return alreadyOpen
        case 404: return gone
        default: return saveFailed
        }
    }

    /// "Due today", "Due tomorrow", "Overdue · Oct 18", "Due Thu, Oct 22".
    ///
    /// A date-only due day is stored at 12:00 UTC, so it is read as a
    /// calendar day in UTC before being compared with today in the user's
    /// own calendar — otherwise a far-west zone would see it a day early.
    static func dueText(
        _ dueAt: Date,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> (text: String, isOverdue: Bool) {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let dueParts = utc.dateComponents([.year, .month, .day], from: dueAt)
        let dueDay = calendar.date(from: dueParts).map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: dueAt)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .month(.abbreviated)
            .day()
        switch days {
        case ..<0:
            return ("Overdue · \(dueDay.formatted(style))", true)
        case 0:
            return ("Due today", false)
        case 1:
            return ("Due tomorrow", false)
        default:
            style = style.weekday(.abbreviated)
            return ("Due \(dueDay.formatted(style))", false)
        }
    }
}
