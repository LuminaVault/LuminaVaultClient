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
        }
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
