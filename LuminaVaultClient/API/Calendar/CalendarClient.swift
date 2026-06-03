// LuminaVaultClient/LuminaVaultClient/API/Calendar/CalendarClient.swift
//
// HER-340 — Google Calendar client backed by `BaseHTTPClient`. The connect
// OAuth handoff (ASWebAuthenticationSession) lives in `CalendarConnectService`;
// this client only speaks the authed JSON endpoints.

import Foundation
import LuminaVaultShared

protocol CalendarClientProtocol: Sendable {
    func status() async throws -> CalendarStatusResponse
    func connect() async throws -> CalendarConnectStartResponse
    func disconnect() async throws
    func events() async throws -> CalendarEventsResponse
    func createEvent(_ request: CalendarCreateEventRequest) async throws -> CalendarEventDTO
}

final class CalendarHTTPClient: CalendarClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient = BaseHTTPClient()) { self.client = client }

    func status() async throws -> CalendarStatusResponse {
        try await client.execute(CalendarEndpoints.GetStatus())
    }

    func connect() async throws -> CalendarConnectStartResponse {
        try await client.execute(CalendarEndpoints.Connect())
    }

    func disconnect() async throws {
        _ = try await client.execute(CalendarEndpoints.Disconnect())
    }

    func events() async throws -> CalendarEventsResponse {
        try await client.execute(CalendarEndpoints.GetEvents())
    }

    func createEvent(_ request: CalendarCreateEventRequest) async throws -> CalendarEventDTO {
        try await client.execute(CalendarEndpoints.CreateEvent(request: request))
    }
}
