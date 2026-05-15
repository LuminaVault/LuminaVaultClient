// LuminaVaultClient/LuminaVaultClient/API/Memory/MemoryQueryHTTPClient.swift
//
// HER-157 — BaseHTTPClient-backed implementation of MemoryQueryClientProtocol.
// Mirrors SettingsHTTPClient (HER-218) shape.

import Foundation

final class MemoryQueryHTTPClient: MemoryQueryClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func query(text: String, limit: Int?) async throws -> QueryResponse {
        try await client.execute(MemoryQueryEndpoints.Query(query: text, limit: limit))
    }
}
