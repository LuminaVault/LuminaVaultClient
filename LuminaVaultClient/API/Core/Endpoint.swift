// LuminaVaultClient/LuminaVaultClient/API/Core/Endpoint.swift
import Foundation

protocol Endpoint {
    associatedtype Response: Decodable
    var path: String { get }
    var method: HTTPMethod { get }
    var body: (any Encodable)? { get }
    var requiresAuth: Bool { get }
    var decoder: JSONDecoder { get }
    var encoder: JSONEncoder { get }
    /// HER-237 — when true, a 401 propagates immediately instead of
    /// triggering the refresh+retry interceptor. Default `!requiresAuth`
    /// covers auth-bootstrap endpoints (login, register, refresh, oauth
    /// exchange, magic-link, phone OTP) so they cannot drive a refresh
    /// loop or mask credential-rejection errors as session expiry.
    var skipsAuthRefresh: Bool { get }
    /// HER-39 — when set, the value is sent as `Idempotency-Key`. The
    /// server idempotency middleware caches the response under
    /// `(tenant_id, key)` so the iOS sync queue can replay the same
    /// request after a network drop without double-creating server rows.
    /// `nil` (default) preserves pre-HER-39 behaviour — no header sent,
    /// every retry is independent.
    var idempotencyKey: UUID? { get }
}

extension Endpoint {
    var requiresAuth: Bool { true }
    var body: (any Encodable)? { nil }
    var decoder: JSONDecoder { .hvDefault }
    var encoder: JSONEncoder { JSONEncoder() }
    var skipsAuthRefresh: Bool { !requiresAuth }
    var idempotencyKey: UUID? { nil }
}

/// Type-erasing wrapper so a JSONEncoder can encode an `any Encodable`
/// value (Encodable existentials don't satisfy `T: Encodable` constraints
/// at the call site).
struct AnyEncodable: Encodable {
    private let _encode: @Sendable (Encoder) throws -> Void
    init(_ wrapped: any Encodable) {
        self._encode = { try wrapped.encode(to: $0) }
    }
    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

extension JSONDecoder {
    static let hvDefault: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        // HER-141: server emits ISO8601 dates (e.g. PhoneStartResponse.expiresAt).
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
