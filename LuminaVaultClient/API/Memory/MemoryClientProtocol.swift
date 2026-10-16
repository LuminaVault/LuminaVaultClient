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

    /// HER-105 — POST /v1/memory/upsert with an optional Space target via the
    /// `?space_id=` query param. A default implementation forwards to
    /// `upsert(_:)` (ignoring the Space) so existing conformers/stubs keep
    /// working without change; the real HTTP client overrides it.
    func upsert(_ request: MemoryUpsertRequest, spaceID: UUID?) async throws -> MemoryUpsertResponse

    /// GET /v1/memory/{id} — fetch one memory for detail popovers and
    /// wikilink previews.
    func get(id: UUID) async throws -> MemoryDTO

    /// HER-290 — PATCH /v1/memory/{id} with a reviewState body. Server
    /// validates only `pending → approved` / `pending → rejected`.
    func patch(id: UUID, _ request: MemoryPatchRequest) async throws -> MemoryDTO

    /// Phase 2 — GET /v1/memory?limit=&offset= for the memory browser.
    func list(limit: Int, offset: Int) async throws -> MemoryListResponse
    func list(limit: Int, offset: Int, healthFilter: MemoryHealthFilter?) async throws -> MemoryListResponse
    /// `kind` narrows the list to one kind of memory; unclassified ones never match.
    func list(
        limit: Int,
        offset: Int,
        healthFilter: MemoryHealthFilter?,
        kind: MemoryKindDTO?
    ) async throws -> MemoryListResponse

    /// Phase 2 — POST /v1/memory/search semantic search.
    func search(_ request: MemorySearchRequest) async throws -> MemorySearchResponse

    /// Phase 2 — DELETE /v1/memory/{id}.
    func delete(id: UUID) async throws

    /// Append-only creator/updater history.
    func provenance(id: UUID) async throws -> MemoryProvenanceResponse

    /// GET /v1/memory/{id}/related — what a memory connects to. `limit` is
    /// clamped server-side.
    func related(id: UUID, limit: Int) async throws -> MemoryRelatedResponse

    /// Provider/model/source counts used by provenance filters.
    func facets() async throws -> MemoryFacetsResponse
    func localSync(cursor: String?, limit: Int) async throws -> LocalMemorySyncResponse
}

extension MemoryClientProtocol {
    func upsert(_ request: MemoryUpsertRequest, spaceID _: UUID?) async throws -> MemoryUpsertResponse {
        try await upsert(request)
    }

    func list(limit: Int, offset: Int, healthFilter _: MemoryHealthFilter?) async throws -> MemoryListResponse {
        try await list(limit: limit, offset: offset)
    }

    func list(
        limit: Int,
        offset: Int,
        healthFilter: MemoryHealthFilter?,
        kind _: MemoryKindDTO?
    ) async throws -> MemoryListResponse {
        try await list(limit: limit, offset: offset, healthFilter: healthFilter)
    }

    func provenance(id _: UUID) async throws -> MemoryProvenanceResponse {
        throw MemoryClientCapabilityError.unsupported
    }

    func facets() async throws -> MemoryFacetsResponse {
        throw MemoryClientCapabilityError.unsupported
    }

    /// Stubs that predate the endpoint connect to nothing, which is what an
    /// older server answers too — the "Connects to" banner simply stays away.
    func related(id: UUID, limit _: Int) async throws -> MemoryRelatedResponse {
        MemoryRelatedResponse(memoryId: id, items: [])
    }

    func localSync(cursor _: String?, limit _: Int) async throws -> LocalMemorySyncResponse {
        throw MemoryClientCapabilityError.unsupported
    }
}

private enum MemoryClientCapabilityError: Error { case unsupported }
