// LuminaVaultClient/LuminaVaultClient/API/Capture/CaptureSafariHTTPClient.swift
//
// HER-257 — BaseHTTPClient-backed implementation. Mirrors MemoryHTTPClient
// shape.

import Foundation

final class CaptureSafariHTTPClient: CaptureSafariClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func capture(_ request: CaptureSafariRequest) async throws -> CaptureSafariResponse {
        try await client.execute(CaptureSafariEndpoints.Capture(request: request))
    }
}
