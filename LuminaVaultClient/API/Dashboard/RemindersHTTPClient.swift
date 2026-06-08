// LuminaVaultClient/LuminaVaultClient/API/Dashboard/RemindersHTTPClient.swift
//
// HER-Reminders — CRUD for /v1/reminders. Firing is server-side; this client
// is list/create/update/delete only.

import Foundation
import LuminaVaultShared

protocol RemindersClientProtocol: Sendable {
    func list(limit: Int?) async throws -> [ReminderDTO]
    func create(_ request: ReminderCreateRequest) async throws -> ReminderDTO
    func update(id: UUID, _ request: ReminderPatchRequest) async throws -> ReminderDTO
    func delete(id: UUID) async throws
    /// HER-55 — classify a chat turn for reminder intent (POST /v1/reminders/detect).
    func detect(text: String) async throws -> ReminderProposalDTO
}

enum RemindersEndpoints {
    struct List: Endpoint {
        typealias Response = ReminderListResponse
        let limit: Int?
        var path: String { limit.map { "/v1/reminders?limit=\($0)" } ?? "/v1/reminders" }
        var method: HTTPMethod { .get }
    }

    struct Create: Endpoint {
        typealias Response = ReminderDTO
        let request: ReminderCreateRequest
        var path: String { "/v1/reminders" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    struct Update: Endpoint {
        typealias Response = ReminderDTO
        let id: UUID
        let request: ReminderPatchRequest
        var path: String { "/v1/reminders/\(id.uuidString.lowercased())" }
        var method: HTTPMethod { .patch }
        var body: (any Encodable)? { request }
    }

    struct Delete: Endpoint {
        typealias Response = EmptyResponse
        let id: UUID
        var path: String { "/v1/reminders/\(id.uuidString.lowercased())" }
        var method: HTTPMethod { .delete }
    }

    struct Detect: Endpoint {
        typealias Response = ReminderProposalDTO
        let text: String
        var path: String { "/v1/reminders/detect" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { ["text": text] }
    }
}

final class RemindersHTTPClient: RemindersClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func list(limit: Int? = nil) async throws -> [ReminderDTO] {
        try await client.execute(RemindersEndpoints.List(limit: limit)).reminders
    }

    func create(_ request: ReminderCreateRequest) async throws -> ReminderDTO {
        try await client.execute(RemindersEndpoints.Create(request: request))
    }

    func update(id: UUID, _ request: ReminderPatchRequest) async throws -> ReminderDTO {
        try await client.execute(RemindersEndpoints.Update(id: id, request: request))
    }

    func delete(id: UUID) async throws {
        _ = try await client.execute(RemindersEndpoints.Delete(id: id))
    }

    func detect(text: String) async throws -> ReminderProposalDTO {
        try await client.execute(RemindersEndpoints.Detect(text: text))
    }
}
