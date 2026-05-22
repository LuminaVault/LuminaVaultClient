// LuminaVaultClient/LuminaVaultClient/API/Notifications/DeviceHTTPClient.swift
//
// HER-214 — BaseHTTPClient-backed APNS device registration.

import Foundation
import LuminaVaultShared

protocol DeviceClientProtocol: Sendable {
    func register(_ body: DeviceRegistrationRequest) async throws -> DeviceRegistrationResponse
    func unregister(token: String) async throws
}

final class DeviceHTTPClient: DeviceClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func register(_ body: DeviceRegistrationRequest) async throws -> DeviceRegistrationResponse {
        try await client.execute(DeviceEndpoints.Register(request: body))
    }

    func unregister(token: String) async throws {
        _ = try await client.execute(DeviceEndpoints.Unregister(token: token))
    }
}
