// LuminaVaultClient/LuminaVaultClient/API/Location/LastKnownLocationClient.swift
//
// Muse Stage C — the one location fix the server keeps so a scheduled job
// (the 07:00 weather check) still works while the phone is asleep. It is
// overwritten on every live read, never a history. Server contract
// (openapi.yaml):
//   GET    /v1/me/location  -> LastKnownLocationResponse
//   DELETE /v1/me/location  -> 204 No Content

import Foundation
import LuminaVaultShared

protocol LastKnownLocationClientProtocol: Sendable {
    func get() async throws -> LastKnownLocationResponse
    func forget() async throws
}

enum LastKnownLocationEndpoints {
    struct Get: Endpoint {
        typealias Response = LastKnownLocationResponse
        var path: String { "/v1/me/location" }
        var method: HTTPMethod { .get }
    }

    struct Forget: Endpoint {
        typealias Response = EmptyResponse
        var path: String { "/v1/me/location" }
        var method: HTTPMethod { .delete }
    }
}

final class LastKnownLocationHTTPClient: LastKnownLocationClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient = BaseHTTPClient()) { self.client = client }

    func get() async throws -> LastKnownLocationResponse {
        try await client.execute(LastKnownLocationEndpoints.Get())
    }

    func forget() async throws {
        _ = try await client.execute(LastKnownLocationEndpoints.Forget())
    }
}
