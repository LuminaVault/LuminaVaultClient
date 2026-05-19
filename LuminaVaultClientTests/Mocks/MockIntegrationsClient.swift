// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockIntegrationsClient.swift
//
// HER-240b — scripted IntegrationsClientProtocol fake. Same shape as
// MockSettingsClient.

@testable import LuminaVaultClient
import Foundation

final class MockIntegrationsClient: IntegrationsClientProtocol, @unchecked Sendable {
    var statusResult: Result<XaiStatusResponse, Error> = .success(.stubDisconnected)
    var startResult: Result<XaiStartResponse, Error> = .success(.stub)
    var completeResult: Result<XaiStatusResponse, Error> = .success(.stubConnected)
    var disconnectResult: Result<XaiStatusResponse, Error> = .success(.stubDisconnected)

    private(set) var calls: [Call] = []
    enum Call: Equatable {
        case status
        case start
        case complete(sessionID: String, callbackURL: String)
        case disconnect
    }

    func getXaiStatus() async throws -> XaiStatusResponse {
        calls.append(.status)
        return try statusResult.get()
    }

    func startXaiConnect() async throws -> XaiStartResponse {
        calls.append(.start)
        return try startResult.get()
    }

    func completeXaiConnect(sessionID: String, callbackURL: String) async throws -> XaiStatusResponse {
        calls.append(.complete(sessionID: sessionID, callbackURL: callbackURL))
        return try completeResult.get()
    }

    func disconnectXai() async throws -> XaiStatusResponse {
        calls.append(.disconnect)
        return try disconnectResult.get()
    }
}

extension XaiStatusResponse {
    static let stubDisconnected = XaiStatusResponse(connected: false, tier: "trial", xaiConnectedAt: nil)
    static let stubConnected = XaiStatusResponse(
        connected: true,
        tier: "pro",
        xaiConnectedAt: Date(timeIntervalSince1970: 1_700_000_000),
    )
}

extension XaiStartResponse {
    static let stub = XaiStartResponse(
        sessionID: "session-stub",
        authorizeURL: "https://accounts.x.ai/authorize?stub=1",
    )
}
