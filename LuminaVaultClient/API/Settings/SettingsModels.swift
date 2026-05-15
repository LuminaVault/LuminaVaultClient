// LuminaVaultClient/LuminaVaultClient/API/Settings/SettingsModels.swift
//
// HER-218 — local mirrors of the BYO-Hermes DTOs published in
// LuminaVaultShared (server tags v0.3.0+). Once HER-213 wires the
// SPM dependency in, these can be replaced with `import LuminaVaultShared`
// imports — the field shapes match 1:1, so the migration is mechanical.

import Foundation

struct HermesConfigGetResponse: Codable, Sendable, Equatable {
    let baseUrl: String
    let hasAuthHeader: Bool
    let verifiedAt: Date?
}

struct HermesConfigPutRequest: Codable, Sendable, Equatable {
    let baseUrl: String
    let authHeader: String?
}

struct HermesConfigTestResponse: Codable, Sendable, Equatable {
    let verifiedAt: Date
}

/// Classified verify-failure body the server returns inside an `error`
/// envelope (`{ "error": "timeout|http_4xx|http_5xx|tls_error" }`). The
/// banner copy on iOS forks on this value.
enum HermesVerifyFailureReason: String, Sendable {
    case timeout
    case http4xx = "http_4xx"
    case http5xx = "http_5xx"
    case tlsError = "tls_error"
    case unknown

    var displayMessage: String {
        switch self {
        case .timeout: "Gateway took too long to respond. Check the URL and your network."
        case .http4xx: "Gateway rejected the request. Your auth token may be wrong."
        case .http5xx: "Gateway reported an internal error. Try again or check the gateway logs."
        case .tlsError: "TLS / certificate error. Make sure the URL uses a valid HTTPS endpoint."
        case .unknown: "Couldn't verify the gateway. Double-check the URL and auth header."
        }
    }
}
