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

    var nousStatusResult: Result<NousStatusResponse, Error> = .success(.stubDisconnected)
    var nousStartResult: Result<NousStartResponse, Error> = .success(.stub)
    var nousCompleteResult: Result<NousStatusResponse, Error> = .success(.stubConnected)
    var nousDisconnectResult: Result<NousStatusResponse, Error> = .success(.stubDisconnected)

    private(set) var calls: [Call] = []
    enum Call: Equatable {
        case status
        case start
        case complete(sessionID: String, callbackURL: String)
        case disconnect
        case nousStatus
        case nousStart
        case nousComplete(sessionID: String)
        case nousDisconnect
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

    func getNousStatus() async throws -> NousStatusResponse {
        calls.append(.nousStatus)
        return try nousStatusResult.get()
    }

    func startNousConnect() async throws -> NousStartResponse {
        calls.append(.nousStart)
        return try nousStartResult.get()
    }

    func completeNousConnect(sessionID: String) async throws -> NousStatusResponse {
        calls.append(.nousComplete(sessionID: sessionID))
        return try nousCompleteResult.get()
    }

    func disconnectNous() async throws -> NousStatusResponse {
        calls.append(.nousDisconnect)
        return try nousDisconnectResult.get()
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

extension NousStatusResponse {
    static let stubDisconnected = NousStatusResponse(connected: false, nousConnectedAt: nil, plan: nil)
    static let stubConnected = NousStatusResponse(
        connected: true,
        nousConnectedAt: Date(timeIntervalSince1970: 1_700_000_000),
        plan: "Hermes Pro",
    )
}

extension NousStartResponse {
    static let stub = NousStartResponse(
        sessionID: "nous-session-stub",
        verifyURL: "https://portal.nousresearch.com/device?user_code=STUB-CODE",
        userCode: "STUB-CODE",
    )
}
