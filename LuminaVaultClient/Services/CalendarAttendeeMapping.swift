// LuminaVaultClient/LuminaVaultClient/Services/CalendarAttendeeMapping.swift
//
// EventKit attendees → `[CalendarAttendeeDTO]` for the calendar sync. The
// pre-meeting brief matches notes on attendee names, and its why line names
// one ("You mentioned Ana in 3 notes"), so the sync carries them.
//
// `EKParticipant` cannot be built outside EventKit, so the mapping runs on
// `CalendarParticipant`, a plain value the tests can make. The wire contract
// the server holds the client to:
//
// * nil leaves the stored attendees alone — only for when they cannot be
//   read at all. EventKit reports an event without attendees as nil, which
//   is an answer ("nobody"), so that is sent as `[]` and clears them.
// * At most 100 are kept, and one with neither a name nor an email is
//   dropped, so the client trims the same way rather than send them.
// * The user's own entry (`isCurrentUser`) is left out: their name is in
//   every meeting, so it matches nothing and would only crowd the query.

import EventKit
import Foundation
import LuminaVaultShared

/// What the mapping needs from one `EKParticipant`.
nonisolated struct CalendarParticipant: Equatable, Sendable {
    let name: String?
    let url: URL?
    let isCurrentUser: Bool

    init(name: String?, url: URL?, isCurrentUser: Bool = false) {
        self.name = name
        self.url = url
        self.isCurrentUser = isCurrentUser
    }
}

nonisolated enum CalendarAttendeeMapping {
    /// The server keeps at most this many per event.
    static let maxAttendees = 100

    /// The attendees to send for one event. `participants` is
    /// `EKEvent.attendees` as values: nil there means no attendees.
    static func attendees(from participants: [CalendarParticipant]?) -> [CalendarAttendeeDTO] {
        var seen = Set<String>()
        var result: [CalendarAttendeeDTO] = []
        for participant in participants ?? [] where !participant.isCurrentUser {
            let email = participant.url.flatMap(email(from:))
            let name = cleaned(participant.name)
            guard name != nil || email != nil else { continue }
            // A participant listed twice (an alias, a forwarded invite) is
            // one person, keyed on the email when there is one.
            let key = email?.lowercased() ?? "name:\(name?.lowercased() ?? "")"
            guard seen.insert(key).inserted else { continue }
            result.append(CalendarAttendeeDTO(name: name, email: email))
            if result.count == maxAttendees { break }
        }
        return result
    }

    /// The address in a `mailto:` URL, without any `?subject=` and with
    /// percent escapes undone. Nil for every other scheme — EventKit also
    /// hands out `urn:` and `http:` participant URLs, which are not emails.
    static func email(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "mailto" else { return nil }
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path
            ?? String(url.absoluteString.dropFirst("mailto:".count))
        let address = cleaned(path.removingPercentEncoding ?? path)
        guard let address, address.contains("@") else { return nil }
        return address
    }

    private static func cleaned(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

nonisolated extension EKEvent {
    /// `attendees` as `CalendarParticipant` values, nil when there are none.
    var calendarParticipants: [CalendarParticipant]? {
        attendees?.map { CalendarParticipant(name: $0.name, url: $0.url, isCurrentUser: $0.isCurrentUser) }
    }
}
