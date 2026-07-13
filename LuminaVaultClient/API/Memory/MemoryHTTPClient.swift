// LuminaVaultClient/LuminaVaultClient/API/Memory/MemoryHTTPClient.swift
//
// HER-34 — BaseHTTPClient-backed implementation of MemoryClientProtocol.

import Foundation
import LuminaVaultShared

final class MemoryHTTPClient: MemoryClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) {
        self.client = client
    }

    func get(id: UUID) async throws -> MemoryDTO {
        try await client.execute(MemoryEndpoints.Get(id: id))
    }

    func upsert(_ request: MemoryUpsertRequest) async throws -> MemoryUpsertResponse {
        try await client.execute(MemoryEndpoints.Upsert(request: request))
    }

    func upsert(_ request: MemoryUpsertRequest, spaceID: UUID?) async throws -> MemoryUpsertResponse {
        try await client.execute(MemoryEndpoints.Upsert(request: request, spaceID: spaceID))
    }

    func patch(id: UUID, _ request: MemoryPatchRequest) async throws -> MemoryDTO {
        try await client.execute(MemoryEndpoints.Patch(id: id, request: request))
    }

    func list(limit: Int, offset: Int) async throws -> MemoryListResponse {
        try await client.execute(MemoryEndpoints.List(limit: limit, offset: offset))
    }

    func list(limit: Int, offset: Int, healthFilter: MemoryHealthFilter?) async throws -> MemoryListResponse {
        try await client.execute(MemoryEndpoints.List(
            limit: limit,
            offset: offset,
            healthFilter: healthFilter
        ))
    }

    func search(_ request: MemorySearchRequest) async throws -> MemorySearchResponse {
        try await client.execute(MemoryEndpoints.Search(request: request))
    }

    func delete(id: UUID) async throws {
        _ = try await client.execute(MemoryEndpoints.Delete(id: id))
    }

    func provenance(id: UUID) async throws -> MemoryProvenanceResponse {
        try await client.execute(MemoryEndpoints.Provenance(id: id))
    }

    func facets() async throws -> MemoryFacetsResponse {
        try await client.execute(MemoryEndpoints.Facets())
    }

    func localSync(cursor: String?, limit: Int = 500) async throws -> LocalMemorySyncResponse {
        try await client.execute(MemoryEndpoints.LocalSync(cursor: cursor, limit: limit))
    }
}
