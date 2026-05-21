// LuminaVaultClient/LuminaVaultClient/API/Memory/MemoryGraphClientProtocol.swift
//
// HER-235 — protocol seam so BrainGraphViewModel can stub the network
// layer in tests without touching BaseHTTPClient.

import Foundation
import LuminaVaultShared

protocol MemoryGraphClientProtocol: Sendable {
    /// GET /v1/memory/graph — derived nodes + edges for the current tenant.
    /// `nil` arguments defer to server defaults (500 / 0.78 / 8).
    func fetchGraph(
        limit: Int?,
        similarityThreshold: Double?,
        maxEdgesPerNode: Int?,
    ) async throws -> MemoryGraphResponse
}
