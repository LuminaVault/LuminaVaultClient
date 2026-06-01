// LuminaVaultClient/LuminaVaultClient/API/Dashboard/ProjectsHTTPClient.swift
//
// HER-Projects — CRUD for /v1/projects (todo containers with live counts).

import Foundation
import LuminaVaultShared

protocol ProjectsClientProtocol: Sendable {
    func list(limit: Int?) async throws -> [ProjectDTO]
    func create(_ request: ProjectCreateRequest) async throws -> ProjectDTO
    func update(id: UUID, _ request: ProjectPatchRequest) async throws -> ProjectDTO
    func delete(id: UUID) async throws
}

enum ProjectsEndpoints {
    struct List: Endpoint {
        typealias Response = ProjectListResponse
        let limit: Int?
        var path: String { limit.map { "/v1/projects?limit=\($0)" } ?? "/v1/projects" }
        var method: HTTPMethod { .get }
    }

    struct Create: Endpoint {
        typealias Response = ProjectDTO
        let request: ProjectCreateRequest
        var path: String { "/v1/projects" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    struct Update: Endpoint {
        typealias Response = ProjectDTO
        let id: UUID
        let request: ProjectPatchRequest
        var path: String { "/v1/projects/\(id.uuidString.lowercased())" }
        var method: HTTPMethod { .patch }
        var body: (any Encodable)? { request }
    }

    struct Delete: Endpoint {
        typealias Response = EmptyResponse
        let id: UUID
        var path: String { "/v1/projects/\(id.uuidString.lowercased())" }
        var method: HTTPMethod { .delete }
    }
}

final class ProjectsHTTPClient: ProjectsClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func list(limit: Int? = nil) async throws -> [ProjectDTO] {
        try await client.execute(ProjectsEndpoints.List(limit: limit)).projects
    }

    func create(_ request: ProjectCreateRequest) async throws -> ProjectDTO {
        try await client.execute(ProjectsEndpoints.Create(request: request))
    }

    func update(id: UUID, _ request: ProjectPatchRequest) async throws -> ProjectDTO {
        try await client.execute(ProjectsEndpoints.Update(id: id, request: request))
    }

    func delete(id: UUID) async throws {
        _ = try await client.execute(ProjectsEndpoints.Delete(id: id))
    }
}
