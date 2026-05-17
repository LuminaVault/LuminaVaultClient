// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockSpacesClient.swift
// HER-35 — scripted SpacesClientProtocol fake for SpacesViewModel tests.

@testable import LuminaVaultClient
import Foundation

final class MockSpacesClient: SpacesClientProtocol, @unchecked Sendable {
    var listResult: Result<[SpaceDTO], Error> = .success([])
    var getResult: Result<SpaceDTO, Error>?
    var createResult: Result<SpaceDTO, Error>?
    var updateResult: Result<SpaceDTO, Error>?
    var deleteError: Error?

    private(set) var calls: [Call] = []
    enum Call: Equatable {
        case list
        case get(UUID)
        case create(CreateSpaceRequest)
        case update(UUID, UpdateSpaceRequest)
        case delete(UUID)

        static func == (lhs: Call, rhs: Call) -> Bool {
            switch (lhs, rhs) {
            case (.list, .list): return true
            case let (.get(a), .get(b)): return a == b
            case let (.delete(a), .delete(b)): return a == b
            case let (.create(a), .create(b)): return a.name == b.name && a.slug == b.slug && a.category == b.category
            case let (.update(idA, a), .update(idB, b)): return idA == idB && a.name == b.name && a.category == b.category
            default: return false
            }
        }
    }

    func list() async throws -> [SpaceDTO] {
        calls.append(.list)
        return try listResult.get()
    }

    func get(id: UUID) async throws -> SpaceDTO {
        calls.append(.get(id))
        guard let result = getResult else {
            throw NSError(domain: "MockSpacesClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "getResult not scripted"])
        }
        return try result.get()
    }

    func create(_ request: CreateSpaceRequest) async throws -> SpaceDTO {
        calls.append(.create(request))
        if let result = createResult { return try result.get() }
        // Default: echo input back as a fresh DTO.
        return SpaceDTO(
            id: UUID(),
            name: request.name,
            slug: request.slug,
            description: request.description,
            color: request.color,
            icon: request.icon,
            category: request.category,
            noteCount: 0,
            createdAt: Date(timeIntervalSince1970: 0),
        )
    }

    func update(id: UUID, _ request: UpdateSpaceRequest) async throws -> SpaceDTO {
        calls.append(.update(id, request))
        guard let result = updateResult else {
            throw NSError(domain: "MockSpacesClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "updateResult not scripted"])
        }
        return try result.get()
    }

    func delete(id: UUID) async throws {
        calls.append(.delete(id))
        if let deleteError { throw deleteError }
    }
}

extension SpaceDTO {
    static func stub(
        id: UUID = UUID(),
        name: String = "AI",
        slug: String = "ai",
        category: String? = "ai",
        noteCount: Int = 0,
    ) -> SpaceDTO {
        SpaceDTO(
            id: id,
            name: name,
            slug: slug,
            description: nil,
            color: nil,
            icon: "sparkles",
            category: category,
            noteCount: noteCount,
            createdAt: Date(timeIntervalSince1970: 0),
        )
    }
}
