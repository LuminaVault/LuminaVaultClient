// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockMemoryClient.swift
// Scripted `MemoryClientProtocol` fake for the memory detail screen and the
// "Connects to" banner: `get`, `related`, `provenance` and `delete` answer
// from scripted results and record their calls; the list/search/upsert face
// is not under test and throws.

@testable import LuminaVaultClient
import Foundation
import LuminaVaultShared

// `@unchecked` because the fake is configured in the test body and read from
// the view model's awaits, all on the main actor in these suites, so the
// accesses never overlap. Same shape as the other scripted mocks here.
final class MockMemoryClient: MemoryClientProtocol, @unchecked Sendable {
    var getResult: Result<MemoryDTO, Error> = .failure(APIError.unauthorized)
    var relatedResult: Result<MemoryRelatedResponse, Error> = .failure(APIError.unauthorized)
    var provenanceResult: Result<MemoryProvenanceResponse, Error> = .failure(APIError.unauthorized)
    var deleteError: Error?

    private(set) var getCalls: [UUID] = []
    private(set) var relatedCalls: [(id: UUID, limit: Int)] = []
    private(set) var deleteCalls: [UUID] = []

    func get(id: UUID) async throws -> MemoryDTO {
        getCalls.append(id)
        return try getResult.get()
    }

    func related(id: UUID, limit: Int) async throws -> MemoryRelatedResponse {
        relatedCalls.append((id, limit))
        return try relatedResult.get()
    }

    func provenance(id _: UUID) async throws -> MemoryProvenanceResponse {
        try provenanceResult.get()
    }

    func delete(id: UUID) async throws {
        deleteCalls.append(id)
        if let deleteError { throw deleteError }
    }

    func upsert(_: MemoryUpsertRequest) async throws -> MemoryUpsertResponse {
        throw APIError.unauthorized
    }

    func patch(id _: UUID, _: MemoryPatchRequest) async throws -> MemoryDTO {
        throw APIError.unauthorized
    }

    func list(limit _: Int, offset _: Int) async throws -> MemoryListResponse {
        throw APIError.unauthorized
    }

    func search(_: MemorySearchRequest) async throws -> MemorySearchResponse {
        throw APIError.unauthorized
    }
}

extension RelatedMemoryDTO {
    static func fixture(
        id: UUID = UUID(),
        snippet: String = "Dentist moved to Thursday",
        kind: MemoryKindDTO? = .fact,
        similarity: Double = 0.82
    ) -> RelatedMemoryDTO {
        RelatedMemoryDTO(
            id: id,
            snippet: snippet,
            kind: kind,
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            spaceId: nil,
            similarity: similarity
        )
    }
}
