// LuminaVaultClient/LuminaVaultClient/API/Core/APIError.swift
import Foundation
import LuminaVaultShared

enum APIError: Error, LocalizedError {
    case invalidURL
    case encodingFailed(Error)
    case networkFailure(Error)
    case httpError(statusCode: Int, data: Data)
    case decodingFailed(Error)
    case unauthorized
    /// HER-188 — server returned `402 Payment Required`. The body MAY carry
    /// hints (`paywall_id`, `required_tier`) that `EntitlementGate` uses to
    /// pick which paywall to present and what tier the user needs to reach.
    /// Both fields are optional: older builds of the server may return a
    /// bare 402, in which case the gate falls back to the local `BillingService`
    /// tier and the `default` offering.
    case paymentRequired(paywallID: String?, requiredTier: UserTier?)
    /// HER-194 — server returned `429 Too Many Requests`. `retryAfter` is
    /// the `Retry-After` header value when present (seconds form only;
    /// HTTP-date form is not parsed). Call sites surface a friendly
    /// daily-cap message; the optional interval lets the UI compute a
    /// countdown when available.
    case rateLimited(retryAfter: TimeInterval?)
    /// The TLS pinning delegate rejected the server's certificate chain and
    /// cancelled the request. URLSession reports this as a bare
    /// `URLError.cancelled`, indistinguishable from a cooperative cancel — so
    /// it gets its own case, or it disappears into `isBenignCancellation` and
    /// the user sees an empty screen instead of a failure. See
    /// `PinningFailureLog` for how the two are told apart.
    case tlsPinningFailed(host: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:              return "Invalid server URL."
        case .encodingFailed:          return "Failed to encode request."
        case .networkFailure(let e):   return e.localizedDescription
        case .httpError(let code, let data):
            if let structured = StructuredAPIError.parse(from: data) {
                return structured.message
            }
            return "Server error (\(code))."
        case .decodingFailed:          return "Unexpected server response."
        case .unauthorized:            return "Session expired. Please sign in again."
        case .paymentRequired(_, let tier):
            if let tier {
                return "This feature requires the \(tier.rawValue.capitalized) plan."
            }
            return "This feature requires an upgraded plan."
        case .rateLimited:
            return "You've hit today's limit. Try again later."
        case .tlsPinningFailed:
            return "Couldn't establish a secure connection to LuminaVault. "
                + "Check for an app update, then try again."
        }
    }

    /// True when the error is a cooperative cancel (SwiftUI `.task` teardown,
    /// refreshable abort, user cancel) — never surface as a user-facing failure.
    ///
    /// A TLS pin rejection also arrives as `URLError.cancelled`, so it is
    /// explicitly excluded: treating it as benign is what let a CA rotation
    /// silently disable the entire app.
    static func isBenignCancellation(_ error: Error) -> Bool {
        if isTLSPinningFailure(error) { return false }
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if case APIError.networkFailure(let underlying) = error {
            return isBenignCancellation(underlying)
        }
        return false
    }

    /// True when this error is a cancel that coincides with a pin rejection
    /// recorded by `PinningFailureLog` inside its correlation window.
    ///
    /// A genuine user cancel occurring within seconds of a pin rejection is
    /// misread as a pinning failure. That trade is deliberate: when pinning is
    /// rejecting, every request is failing anyway, and a false "secure
    /// connection" message beats a silent empty screen.
    static func isTLSPinningFailure(_ error: Error) -> Bool {
        if case APIError.tlsPinningFailed = error { return true }
        if case APIError.networkFailure(let underlying) = error {
            return isTLSPinningFailure(underlying)
        }
        guard let urlError = error as? URLError, urlError.code == .cancelled else { return false }
        if let host = urlError.failingURL?.host {
            return PinningFailureLog.recentFailure(for: host) != nil
        }
        return PinningFailureLog.hasRecentFailure()
    }

    /// Wraps a raw transport error, promoting pin rejections out of the
    /// generic `.networkFailure` bucket so they carry a real message.
    static func transport(_ error: Error) -> APIError {
        guard isTLSPinningFailure(error) else { return .networkFailure(error) }
        let host = (error as? URLError)?.failingURL?.host
        return .tlsPinningFailed(host: host)
    }
}

extension Error {
    /// Convenience for call sites that catch `any Error`.
    var isBenignCancellation: Bool {
        APIError.isBenignCancellation(self)
    }
}

/// HER-188 — best-effort decode of the server's 402 response body. Property
/// names use the camelCase form that `JSONDecoder.hvDefault.keyDecodingStrategy
/// = .convertFromSnakeCase` produces from snake-case JSON keys. Any missing
/// key is tolerated so a bare 402 still produces a `.paymentRequired(nil, nil)`.
struct PaymentRequiredBody: Decodable {
    let paywallID: String?
    let requiredTier: UserTier?

    private enum CodingKeys: String, CodingKey {
        // Snake → camel conversion lands `paywall_id` as `paywallId` (lowercase
        // `d`), so we declare the converted name here. Same for
        // `required_tier` → `requiredTier`.
        case paywallID = "paywallId"
        case requiredTier
    }
}
