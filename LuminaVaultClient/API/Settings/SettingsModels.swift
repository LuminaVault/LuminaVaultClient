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

/// Classified verify-failure code the server returns in a Hummingbird error
/// envelope (`{ "error": { "message": "http_4xx" } }`). Every probe failure
/// comes back as HTTP 502 regardless of what went wrong, so the status code
/// carries no information — this value does. Mirrors
/// `HermesConfigController.TestError` on the server.
enum HermesVerifyFailureReason: String, Sendable {
    case timeout
    case http4xx = "http_4xx"
    case http5xx = "http_5xx"
    case tlsError = "tls_error"
    case ssrfRejected = "ssrf_rejected"
    case decryptFailed = "decrypt_failed"
    case unreachable
    case unknown

    var displayMessage: String {
        switch self {
        case .timeout:
            "Hermes took too long to respond. Check that it's running and reachable from the internet."
        case .http4xx:
            "Hermes rejected the request. Check the URL points at the API server (port 8642, not the dashboard on 9119) and that the token matches API_SERVER_KEY."
        case .http5xx:
            "Hermes reported an internal error. Try again or check its logs."
        case .tlsError:
            "TLS / certificate error. Make sure the URL uses a valid HTTPS endpoint — self-signed certificates aren't accepted."
        case .ssrfRejected:
            "That address isn't allowed. It must be a public HTTPS hostname — private, loopback and link-local addresses are blocked."
        case .decryptFailed:
            "Stored credentials couldn't be read. Re-enter your token and save again."
        case .unreachable:
            "Couldn't reach Hermes. If it's on a tailnet or private network, expose it with a Cloudflare Tunnel or a public HTTPS hostname."
        case .unknown:
            "Couldn't verify Hermes. Double-check the URL and auth header."
        }
    }
}
