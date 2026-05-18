// LuminaVaultClient/LuminaVaultClient/API/Memory/MemoryHTTPClient.swift
//
// HER-34 — BaseHTTPClient-backed implementation of MemoryClientProtocol.

import Foundation
import LuminaVaultShared

final class MemoryHTTPClient: MemoryClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func upsert(_ request: MemoryUpsertRequest) async throws -> MemoryUpsertResponse {
        try await client.execute(MemoryEndpoints.Upsert(request: request))
    }
}
