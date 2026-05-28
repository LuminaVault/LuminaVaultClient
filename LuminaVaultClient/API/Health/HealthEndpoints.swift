// LuminaVaultClient/LuminaVaultClient/API/Health/HealthEndpoints.swift
import Foundation

enum HealthEndpoints {
    /// `POST /v1/health` — bulk-insert HealthKit / Google Fit / manual events.
    /// Server validates per-event; malformed rows are skipped, not fatal.
    struct Ingest: Endpoint {
        typealias Response = HealthIngestResponse
        let events: [HealthEventInput]

        var path: String { "/v1/health" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { true }
        var body: (any Encodable)? { HealthIngestRequest(events: events) }
        var encoder: JSONEncoder { .lvHealth }
        var decoder: JSONDecoder { .lvHealth }
    }

    /// HER-118 — `GET /v1/health/daily?type=&days=` fetches a fixed-length
    /// chronological day window for the given event type, suitable for
    /// sparkline rendering without local bucketing.
    struct Daily: Endpoint {
        typealias Response = HealthDailyResponse
        let type: String
        let days: Int

        init(type: String, days: Int = 7) {
            self.type = type
            self.days = days
        }

        var path: String { "/v1/health/daily?type=\(type)&days=\(days)" }
        var method: HTTPMethod { .get }
        var requiresAuth: Bool { true }
        var decoder: JSONDecoder { .lvHealth }
    }

    /// HER-118 — `GET /v1/health?type=&limit=` returns the most-recent raw
    /// samples for the detail screen. Server clamps `limit` to [1, 200].
    struct ListSamples: Endpoint {
        typealias Response = HealthListResponse
        let type: String
        let limit: Int

        init(type: String, limit: Int = 50) {
            self.type = type
            self.limit = limit
        }

        var path: String { "/v1/health?type=\(type)&limit=\(limit)" }
        var method: HTTPMethod { .get }
        var requiresAuth: Bool { true }
        var decoder: JSONDecoder { .lvHealth }
    }
}
