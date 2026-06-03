// LuminaVaultClient/LuminaVaultClient/API/Calendar/CalendarEndpoints.swift
//
// HER-340 — Google Calendar endpoints. Server contract (openapi.yaml):
//   GET    /v1/calendar/status      -> CalendarStatusResponse
//   POST   /v1/calendar/connect     -> CalendarConnectStartResponse
//   POST   /v1/calendar/disconnect  -> 204 No Content
//   GET    /v1/calendar/events      -> CalendarEventsResponse
//   POST   /v1/calendar/events      -> CalendarEventDTO
//
// Dates are iso8601 + keys camelCase both directions (Hummingbird default
// coders), so the create request encoder sets `.iso8601` and does NOT
// snake-case keys; responses decode via the standard `.hvDefault`.

import Foundation
import LuminaVaultShared

enum CalendarEndpoints {
    struct GetStatus: Endpoint {
        typealias Response = CalendarStatusResponse
        var path: String { "/v1/calendar/status" }
        var method: HTTPMethod { .get }
    }

    struct Connect: Endpoint {
        typealias Response = CalendarConnectStartResponse
        var path: String { "/v1/calendar/connect" }
        var method: HTTPMethod { .post }
    }

    struct Disconnect: Endpoint {
        typealias Response = EmptyResponse
        var path: String { "/v1/calendar/disconnect" }
        var method: HTTPMethod { .post }
    }

    struct GetEvents: Endpoint {
        typealias Response = CalendarEventsResponse
        var path: String { "/v1/calendar/events" }
        var method: HTTPMethod { .get }
    }

    struct CreateEvent: Endpoint {
        typealias Response = CalendarEventDTO
        let request: CalendarCreateEventRequest
        var path: String { "/v1/calendar/events" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
        var encoder: JSONEncoder {
            let e = JSONEncoder()
            e.dateEncodingStrategy = .iso8601
            return e
        }
    }
}
