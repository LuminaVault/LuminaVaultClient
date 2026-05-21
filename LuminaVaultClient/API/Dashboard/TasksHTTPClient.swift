// LuminaVaultClient/LuminaVaultClient/API/Dashboard/TasksHTTPClient.swift
//
// HER-244 — BaseHTTPClient-backed implementation of TasksClientProtocol.

import Foundation
import LuminaVaultShared

protocol TasksClientProtocol: Sendable {
    func list(state: TaskState?, limit: Int?) async throws -> TaskListResponse
}

final class TasksHTTPClient: TasksClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func list(state: TaskState? = nil, limit: Int? = nil) async throws -> TaskListResponse {
        try await client.execute(TasksEndpoints.List(state: state, limit: limit))
    }
}
