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
}

extension Endpoint {
    var requiresAuth: Bool { true }
    var body: (any Encodable)? { nil }
    var decoder: JSONDecoder { .hvDefault }
    var encoder: JSONEncoder { JSONEncoder() }
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
        return d
    }()
}
