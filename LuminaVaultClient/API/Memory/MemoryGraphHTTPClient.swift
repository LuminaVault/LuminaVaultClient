// LuminaVaultClient/LuminaVaultClient/API/Memory/MemoryGraphHTTPClient.swift
//
// HER-235 — BaseHTTPClient-backed implementation of MemoryGraphClientProtocol.
// Mirrors MemoryQueryHTTPClient (HER-157) shape.

import Foundation
import LuminaVaultShared

final class MemoryGraphHTTPClient: MemoryGraphClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func fetchGraph(
        limit: Int?,
        similarityThreshold: Double?,
        maxEdgesPerNode: Int?,
    ) async throws -> MemoryGraphResponse {
        try await client.execute(MemoryGraphEndpoints.Graph(
            limit: limit,
            similarityThreshold: similarityThreshold,
            maxEdgesPerNode: maxEdgesPerNode,
        ))
    }
}
