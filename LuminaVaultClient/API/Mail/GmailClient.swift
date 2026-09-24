// LuminaVaultClient/LuminaVaultClient/API/Mail/GmailClient.swift
//
// Muse Stage C — Gmail as a read-only data source for Hermie. Gmail is an
// incremental `gmail.readonly` scope on the same Google OAuth grant as
// Calendar, so connect returns the same one-field start response and the
// handoff reuses `CalendarConnectService` (it parses only `status`/`reason`
// off the `luminavault://oauth/google-gmail` callback). Server contract
// (openapi.yaml):
//   GET  /v1/mail/gmail/status      -> GmailStatusResponse
//   POST /v1/mail/gmail/connect     -> CalendarConnectStartResponse
//   POST /v1/mail/gmail/disconnect  -> 204 No Content

import Foundation
import LuminaVaultShared

protocol GmailClientProtocol: Sendable {
    func status() async throws -> GmailStatusResponse
    func connect() async throws -> CalendarConnectStartResponse
    func disconnect() async throws
}

enum GmailEndpoints {
    struct GetStatus: Endpoint {
        typealias Response = GmailStatusResponse
        var path: String { "/v1/mail/gmail/status" }
        var method: HTTPMethod { .get }
    }

    struct Connect: Endpoint {
        typealias Response = CalendarConnectStartResponse
        var path: String { "/v1/mail/gmail/connect" }
        var method: HTTPMethod { .post }
    }

    struct Disconnect: Endpoint {
        typealias Response = EmptyResponse
        var path: String { "/v1/mail/gmail/disconnect" }
        var method: HTTPMethod { .post }
    }
}

final class GmailHTTPClient: GmailClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient = BaseHTTPClient()) { self.client = client }

    func status() async throws -> GmailStatusResponse {
        try await client.execute(GmailEndpoints.GetStatus())
    }

    func connect() async throws -> CalendarConnectStartResponse {
        try await client.execute(GmailEndpoints.Connect())
    }

    func disconnect() async throws {
        _ = try await client.execute(GmailEndpoints.Disconnect())
    }
}
