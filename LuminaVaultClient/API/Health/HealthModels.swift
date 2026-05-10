// LuminaVaultClient/LuminaVaultClient/API/Health/HealthModels.swift
import Foundation

/// One sample as POSTed to `/v1/health`. Matches server DTO. Use ISO-8601
/// dates; the encoder configured below emits `Z`-suffixed fractional UTC.
struct HealthEventInput: Codable, Sendable {
    let type: String
    let recordedAt: Date
    let valueNumeric: Double?
    let valueText: String?
    let unit: String?
    let source: String?
    let metadata: [String: String]?
}

struct HealthIngestRequest: Codable, Sendable {
    let events: [HealthEventInput]
}

struct HealthIngestedRef: Codable, Sendable {
    let id: UUID
    let type: String
    let recordedAt: Date
}

struct HealthIngestResponse: Codable, Sendable {
    let inserted: Int
    let skipped: Int
    let events: [HealthIngestedRef]
}

extension JSONEncoder {
    /// Server expects ISO-8601 timestamps and snake_case keys.
    static let lvHealth: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
}

extension JSONDecoder {
    /// Server emits snake_case; flip on the way in.
    static let lvHealth: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}
