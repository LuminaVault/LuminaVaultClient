// LuminaVaultClient/LuminaVaultClient/API/Health/HealthModels.swift
// HER-213: HealthEventInput / HealthIngestedRef / HealthIngestResponse
// come from LuminaVaultShared. HealthIngestRequest stays local for now
// (not yet in Shared). JSON coders are client-only configuration.
import Foundation
@_exported import LuminaVaultShared

typealias HealthEventInput = LuminaVaultShared.HealthEventInput
typealias HealthIngestedRef = LuminaVaultShared.HealthIngestedRef
typealias HealthIngestResponse = LuminaVaultShared.HealthIngestResponse

struct HealthIngestRequest: Codable, Sendable {
    let events: [HealthEventInput]
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
