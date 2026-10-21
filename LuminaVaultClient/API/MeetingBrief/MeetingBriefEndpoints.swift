// LuminaVaultClient/LuminaVaultClient/API/MeetingBrief/MeetingBriefEndpoints.swift
//
// The pre-meeting brief (opt-in): the notes that bear on one upcoming
// meeting.
//
// GET /v1/calendar/events/{id}/brief → `MeetingBriefResponse` — the event,
// at most five notes nearest first (empty when nothing passes the server's
// floor), and one deterministic why line. 404 for an event the caller does
// not have. The id is the one in the push's `luminavault://meeting/<id>`.
//
// The server writes camelCase and RFC 3339 dates, the calendar endpoints'
// own `.lvCalendar` shape.

import Foundation
import LuminaVaultShared

nonisolated enum MeetingBriefEndpoints {
    nonisolated struct Get: Endpoint {
        typealias Response = MeetingBriefResponse
        let eventID: UUID

        var path: String {
            "/v1/calendar/events/\(eventID.uuidString.lowercased())/brief"
        }

        var method: HTTPMethod {
            .get
        }

        var decoder: JSONDecoder {
            .lvCalendar
        }

        /// Opened from a quiet push; a 402 shows in the sheet rather than
        /// sliding a paywall over it.
        var presentsPaywallOn402: Bool {
            false
        }
    }
}
