// LuminaVaultClient/LuminaVaultClient/API/Spaces/SpacesHTTPClient.swift
import Foundation

final class SpacesHTTPClient: SpacesClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func list() async throws -> [SpaceDTO] {
        try await client.execute(SpacesEndpoints.List()).spaces
    }

    func get(id: UUID) async throws -> SpaceDTO {
        try await client.execute(SpacesEndpoints.GetOne(id: id))
    }

    func create(_ request: CreateSpaceRequest) async throws -> SpaceDTO {
        try await client.execute(SpacesEndpoints.Create(request: request))
    }

    func update(id: UUID, _ request: UpdateSpaceRequest) async throws -> SpaceDTO {
        try await client.execute(SpacesEndpoints.Update(id: id, request: request))
    }

    func delete(id: UUID) async throws {
        _ = try await client.execute(SpacesEndpoints.Delete(id: id))
    }
}
