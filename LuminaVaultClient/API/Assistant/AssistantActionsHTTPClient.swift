// LuminaVaultClient/LuminaVaultClient/API/Assistant/AssistantActionsHTTPClient.swift
//
// Quick Assistant action resolution. Server contract:
//   POST /v1/assistant/actions/:id/confirm -> AssistantActionResolutionDTO
//   POST /v1/assistant/actions/:id/cancel  -> AssistantActionResolutionDTO
//   404 (ErrorEnvelope) when the action does not exist for this user.
//
// Neither call has a request body: the server runs the action from the
// arguments it stored when the card was shown. Decisions about expiry belong
// to the server (`status: expired`), never to the client's clock.
import Foundation
import LuminaVaultShared

protocol AssistantActionsClientProtocol: Sendable {
    func confirm(_ id: UUID) async throws -> AssistantActionResolutionDTO
    func cancel(_ id: UUID) async throws -> AssistantActionResolutionDTO
}

nonisolated enum AssistantEndpoints {
    nonisolated struct Confirm: Endpoint {
        // A failed confirm is shown on the card, never as an app-root paywall.
        var presentsPaywallOn402: Bool { false }
        typealias Response = AssistantActionResolutionDTO
        let id: UUID
        var path: String { "/v1/assistant/actions/\(id.uuidString.lowercased())/confirm" }
        var method: HTTPMethod { .post }
    }

    nonisolated struct Cancel: Endpoint {
        var presentsPaywallOn402: Bool { false }
        typealias Response = AssistantActionResolutionDTO
        let id: UUID
        var path: String { "/v1/assistant/actions/\(id.uuidString.lowercased())/cancel" }
        var method: HTTPMethod { .post }
    }
}

final class AssistantActionsHTTPClient: AssistantActionsClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) {
        self.client = client
    }

    func confirm(_ id: UUID) async throws -> AssistantActionResolutionDTO {
        try await client.execute(AssistantEndpoints.Confirm(id: id))
    }

    func cancel(_ id: UUID) async throws -> AssistantActionResolutionDTO {
        try await client.execute(AssistantEndpoints.Cancel(id: id))
    }
}
