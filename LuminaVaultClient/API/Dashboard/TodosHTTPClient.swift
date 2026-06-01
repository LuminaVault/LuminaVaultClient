// LuminaVaultClient/LuminaVaultClient/API/Dashboard/TodosHTTPClient.swift
//
// HER-Todos — CRUD for /v1/todos (note-backed to-do items).

import Foundation
import LuminaVaultShared

protocol TodosClientProtocol: Sendable {
    func list() async throws -> [TodoDTO]
    func create(_ request: TodoCreateRequest) async throws -> TodoDTO
    func update(id: UUID, _ request: TodoPatchRequest) async throws -> TodoDTO
    func delete(id: UUID) async throws
}

enum TodosEndpoints {
    struct List: Endpoint {
        typealias Response = TodoListResponse
        var path: String { "/v1/todos" }
        var method: HTTPMethod { .get }
    }

    struct Create: Endpoint {
        typealias Response = TodoDTO
        let request: TodoCreateRequest
        var path: String { "/v1/todos" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    struct Update: Endpoint {
        typealias Response = TodoDTO
        let id: UUID
        let request: TodoPatchRequest
        var path: String { "/v1/todos/\(id.uuidString.lowercased())" }
        var method: HTTPMethod { .patch }
        var body: (any Encodable)? { request }
    }

    struct Delete: Endpoint {
        typealias Response = EmptyResponse
        let id: UUID
        var path: String { "/v1/todos/\(id.uuidString.lowercased())" }
        var method: HTTPMethod { .delete }
    }
}

final class TodosHTTPClient: TodosClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func list() async throws -> [TodoDTO] {
        try await client.execute(TodosEndpoints.List()).todos
    }

    func create(_ request: TodoCreateRequest) async throws -> TodoDTO {
        try await client.execute(TodosEndpoints.Create(request: request))
    }

    func update(id: UUID, _ request: TodoPatchRequest) async throws -> TodoDTO {
        try await client.execute(TodosEndpoints.Update(id: id, request: request))
    }

    func delete(id: UUID) async throws {
        _ = try await client.execute(TodosEndpoints.Delete(id: id))
    }
}
