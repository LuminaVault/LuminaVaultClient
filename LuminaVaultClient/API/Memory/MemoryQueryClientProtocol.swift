// LuminaVaultClient/LuminaVaultClient/API/Memory/MemoryQueryClientProtocol.swift
//
// HER-157 — protocol seam so the ViewModel + share extension can stub
// the network layer in tests without touching BaseHTTPClient.

import Foundation

protocol MemoryQueryClientProtocol: Sendable {
    /// POST /v1/query — Hermes synthesis + ranked memory hits for the
    /// given text. Limit is server-side; nil = server default.
    func query(text: String, limit: Int?) async throws -> QueryResponse
}
