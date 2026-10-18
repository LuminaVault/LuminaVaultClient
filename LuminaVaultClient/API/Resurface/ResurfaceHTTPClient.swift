// LuminaVaultClient/LuminaVaultClient/API/Resurface/ResurfaceHTTPClient.swift
//
// BaseHTTPClient-backed `ResurfaceClientProtocol`. Built by
// `AppState.makeResurfaceClient()`.

import Foundation
import LuminaVaultShared

final class ResurfaceHTTPClient: ResurfaceClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) {
        self.client = client
    }

    func resurface(limit: Int) async throws -> ResurfaceResponse {
        try await client.execute(ResurfaceEndpoints.Get(limit: limit))
    }
}
