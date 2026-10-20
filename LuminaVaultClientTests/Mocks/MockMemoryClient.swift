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
    var reviewResult: Result<MemoryReviewResponse, Error> = .failure(APIError.unauthorized)
    private(set) var reviewCalls: [(id: UUID, action: MemoryReviewAction?)] = []
    /// Throws by default, as it always did; script a success to use it.
    var patchResult: Result<MemoryDTO, Error> = .failure(APIError.unauthorized)
    private(set) var patchCalls: [(id: UUID, request: MemoryPatchRequest)] = []

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

    func review(id: UUID, action: MemoryReviewAction?) async throws -> MemoryReviewResponse {
        reviewCalls.append((id, action))
        return try reviewResult.get()
    }

    func upsert(_: MemoryUpsertRequest) async throws -> MemoryUpsertResponse {
        throw APIError.unauthorized
    }

    func patch(id: UUID, _ request: MemoryPatchRequest) async throws -> MemoryDTO {
        patchCalls.append((id, request))
        return try patchResult.get()
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
