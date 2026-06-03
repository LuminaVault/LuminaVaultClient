// LuminaVaultClient/LuminaVaultClient/API/Calendar/CalendarSyncEndpoints.swift
//
// Apple Calendar (EventKit) selective-sync — pushes derived event metadata
// to the server cache (`calendar_events`, source `apple_eventkit`) so the
// `calendar_query` Hermes tool can read the user's schedule in the
// background without a live device round-trip. Mirrors `HealthEndpoints`.

import Foundation
import LuminaVaultShared

enum CalendarSyncEndpoints {
    /// `POST /v1/calendar/sync` — batch-upsert EventKit event deltas.
    /// Server consent-gates on the `calendar` domain, upserts by
    /// `(tenant_id, source, external_id)` with last-writer-wins on
    /// `remoteUpdatedAt`, and tombstones cancelled events.
    struct Sync: Endpoint {
        typealias Response = AppleSyncResponse
        let events: [AppleCalendarEventInput]

        var path: String { "/v1/calendar/sync" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { true }
        var body: (any Encodable)? { AppleCalendarSyncRequest(events: events) }
        var encoder: JSONEncoder { .lvCalendar }
        var decoder: JSONDecoder { .lvCalendar }
    }
}

extension JSONEncoder {
    /// ISO8601 dates to match the server's decoder (the `calendar_events`
    /// timestamps round-trip as RFC3339). No key conversion — the shared
    /// DTOs already use the exact wire field names.
    static let lvCalendar: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let lvCalendar: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
