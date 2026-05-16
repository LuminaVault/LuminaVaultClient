// LuminaVaultClient/LuminaVaultClient/API/Settings/SettingsModels.swift
// HER-213: BYO-Hermes DTOs sourced from LuminaVaultShared. Retroactive
// Equatable conformances added here for SwiftUI diffing.
// HermesVerifyFailureReason is iOS-only display logic — stays local.
import Foundation
@_exported import LuminaVaultShared

typealias HermesConfigGetResponse = LuminaVaultShared.HermesConfigGetResponse
typealias HermesConfigPutRequest = LuminaVaultShared.HermesConfigPutRequest
typealias HermesConfigTestResponse = LuminaVaultShared.HermesConfigTestResponse

extension LuminaVaultShared.HermesConfigGetResponse: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.baseUrl == rhs.baseUrl
            && lhs.hasAuthHeader == rhs.hasAuthHeader
            && lhs.verifiedAt == rhs.verifiedAt
    }
}

extension LuminaVaultShared.HermesConfigPutRequest: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.baseUrl == rhs.baseUrl && lhs.authHeader == rhs.authHeader
    }
}

extension LuminaVaultShared.HermesConfigTestResponse: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.verifiedAt == rhs.verifiedAt
    }
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
