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
}
