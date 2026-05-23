// LuminaVaultClient/LuminaVaultClient/API/Memory/MemoryClientProtocol.swift
//
// HER-34 — write-side memory client. `MemoryQueryClientProtocol` covers
// the read side (`POST /v1/query`); this one covers `POST /v1/memory/upsert`
// for Vault Capture.

import Foundation
import LuminaVaultShared

protocol MemoryClientProtocol: Sendable {
    /// POST /v1/memory/upsert — persist a Memory row for the authenticated
    /// tenant. Geo fields are optional per HER-207.
    func upsert(_ request: MemoryUpsertRequest) async throws -> MemoryUpsertResponse

    /// GET /v1/memory/{id} — fetch one memory for detail popovers and
    /// wikilink previews.
    func get(id: UUID) async throws -> MemoryDTO
}
