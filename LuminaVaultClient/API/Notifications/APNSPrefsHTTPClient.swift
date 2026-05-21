// LuminaVaultClient/LuminaVaultClient/API/Notifications/APNSPrefsHTTPClient.swift
//
// HER-179 — BaseHTTPClient-backed APNS category opt-out.

import Foundation
import LuminaVaultShared

protocol APNSPrefsClientProtocol: Sendable {
    func get() async throws -> APNSCategoryPrefsResponse
    func put(_ body: APNSCategoryPrefsPutRequest) async throws -> APNSCategoryPrefsResponse
}

final class APNSPrefsHTTPClient: APNSPrefsClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func get() async throws -> APNSCategoryPrefsResponse {
        try await client.execute(APNSPrefsEndpoints.Get())
    }

    func put(_ body: APNSCategoryPrefsPutRequest) async throws -> APNSCategoryPrefsResponse {
        try await client.execute(APNSPrefsEndpoints.Put(request: body))
    }
}
