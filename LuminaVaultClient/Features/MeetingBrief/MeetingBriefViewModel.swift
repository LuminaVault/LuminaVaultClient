// LuminaVaultClient/LuminaVaultClient/Features/MeetingBrief/MeetingBriefViewModel.swift
//
// The pre-meeting brief (opt-in): one upcoming meeting — its title, time,
// place and people — the server's one-line why, and the notes that bear on
// it, nearest first. Opened from `luminavault://meeting/<eventId>`, the deep
// link of the quiet push that goes out about half an hour before.
//
// Read-only. A note opens in `MemoryDetailSheet`; there is nothing to answer
// here, so there is nothing optimistic either. An event the server does not
// have for this account (deleted since, or a stale link) is its own state
// rather than a generic failure, so the sheet can say what happened.

import Foundation
import LuminaVaultShared
import Observation

@Observable
@MainActor
final class MeetingBriefViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// 404: no such event in the caller's calendar.
        case notFound
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var brief: MeetingBriefResponse?

    let eventID: UUID
    private let client: any MeetingBriefClientProtocol
    private let locale: Locale
    private let timeZone: TimeZone

    init(
        eventID: UUID,
        client: any MeetingBriefClientProtocol,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        self.eventID = eventID
        self.client = client
        self.locale = locale
        self.timeZone = timeZone
    }

    // MARK: - Load

    /// First load, "Try again" and pull-to-refresh. A failed refresh keeps
    /// what is on screen.
    func load() async {
        do {
            brief = try await client.brief(eventID: eventID)
            phase = .loaded
        } catch {
            if case .loaded = phase { return }
            if case let APIError.httpError(statusCode, _) = error, statusCode == 404 {
                phase = .notFound
            } else {
                phase = .failed("Couldn't load this meeting's brief.")
            }
        }
    }

    // MARK: - What the sheet shows

    var memories: [MeetingBriefMemoryDTO] {
        brief?.memories ?? []
    }

    /// Loaded, and nothing the user saved passes the server's floor.
    var isEmpty: Bool {
        phase == .loaded && memories.isEmpty
    }

    /// The server's why, when there is something it explains. With no notes
    /// it would only repeat the empty state.
    var whyText: String? {
        guard !memories.isEmpty, let why = brief?.why, !why.isEmpty else { return nil }
        return why
    }

    /// "Wed, Oct 21 · 2:30 – 3:00 PM".
    var timeRangeText: String? {
        guard let event = brief?.event else { return nil }
        return Self.timeRangeText(start: event.startsAt, end: event.endsAt, locale: locale, timeZone: timeZone)
    }

    var locationText: String? {
        guard let location = brief?.event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty
        else { return nil }
        return location
    }

    /// "Ana Silva, Rui and joana@example.com" — names where there are names.
    var attendeesText: String? {
        guard let attendees = brief?.event.attendees else { return nil }
        return Self.attendeesText(attendees, locale: locale)
    }

    /// "Decision · Oct 3" under a note.
    func metaText(for memory: MeetingBriefMemoryDTO) -> String {
        let date = memory.createdAt.formatted(
            Date.FormatStyle(locale: locale, timeZone: timeZone).month(.abbreviated).day()
        )
        guard let kind = Self.kindLabel(memory.kind) else { return date }
        return "\(kind) · \(date)"
    }

    // MARK: - Formatting

    nonisolated static func timeRangeText(start: Date, end: Date, locale: Locale, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
            .weekday(.abbreviated).month(.abbreviated).day()
        let time = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
            .hour().minute()
        let startTime = start.formatted(time)
        guard end > start else { return "\(start.formatted(day)) · \(startTime)" }
        guard calendar.isDate(start, inSameDayAs: end) else {
            return "\(start.formatted(day)) \(startTime) – \(end.formatted(day)) \(end.formatted(time))"
        }
        return "\(start.formatted(day)) · \(startTime) – \(end.formatted(time))"
    }

    /// At most five shown by name; the rest are counted.
    nonisolated static let shownAttendees = 5

    nonisolated static func attendeesText(_ attendees: [CalendarAttendeeDTO], locale: Locale) -> String? {
        let labels = attendees.compactMap { attendee -> String? in
            if let name = attendee.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
            if let email = attendee.email?.trimmingCharacters(in: .whitespaces), !email.isEmpty { return email }
            return nil
        }
        guard !labels.isEmpty else { return nil }
        guard labels.count > shownAttendees else {
            return labels.formatted(.list(type: .and).locale(locale))
        }
        let rest = labels.count - shownAttendees
        let shown = labels.prefix(shownAttendees).joined(separator: ", ")
        return "\(shown) and \(rest) more"
    }

    /// The raw kind, readable: "decision" → "Decision", "open_question" →
    /// "Open question". A kind this build has never heard of still shows.
    nonisolated static func kindLabel(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let words = raw.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst().lowercased()
    }
}
