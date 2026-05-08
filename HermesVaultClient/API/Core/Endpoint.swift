// HermesVaultClient/HermesVaultClient/API/Core/Endpoint.swift
import Foundation

protocol Endpoint {
    associatedtype Response: Decodable
    var path: String { get }
    var method: HTTPMethod { get }
    var body: (any Encodable)? { get }
    var requiresAuth: Bool { get }
    var decoder: JSONDecoder { get }
}

extension Endpoint {
    var requiresAuth: Bool { true }
    var body: (any Encodable)? { nil }
    var decoder: JSONDecoder { .hvDefault }
}

extension JSONDecoder {
    static let hvDefault: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}
