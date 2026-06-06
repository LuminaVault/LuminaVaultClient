// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockSettingsClient.swift
//
// HER-218 — scripted SettingsClientProtocol fake. Each call route can be
// pre-loaded with either a success value or an Error; tests assert on the
// recorded call list after exercising the ViewModel.

@testable import LuminaVaultClient
import Foundation

final class MockSettingsClient: SettingsClientProtocol, @unchecked Sendable {
    var getResult: Result<HermesConfigGetResponse?, Error> = .success(nil)
    var putResult: Result<HermesConfigGetResponse, Error> = .success(.stubUnverified)
    var deleteError: Error?
    var testResult: Result<HermesConfigTestResponse, Error> = .success(.init(verifiedAt: Date(timeIntervalSince1970: 0)))

    private(set) var calls: [Call] = []
    enum Call: Equatable {
        case get
        case put(baseUrl: String, authHeader: String?)
        case delete
        case test
    }

    func getHermesConfig() async throws -> HermesConfigGetResponse? {
        calls.append(.get)
        return try getResult.get()
    }

    func putHermesConfig(baseUrl: String, authHeader: String?, name: String?) async throws -> HermesConfigGetResponse {
        calls.append(.put(baseUrl: baseUrl, authHeader: authHeader))
        return try putResult.get()
    }

    func deleteHermesConfig() async throws {
        calls.append(.delete)
        if let deleteError { throw deleteError }
    }

    func testHermesConfig() async throws -> HermesConfigTestResponse {
        calls.append(.test)
        return try testResult.get()
    }
}

extension HermesConfigGetResponse {
    static let stubUnverified = HermesConfigGetResponse(
        baseUrl: "https://hermes.example.com",
        hasAuthHeader: true,
        verifiedAt: nil,
    )
    static let stubVerified = HermesConfigGetResponse(
        baseUrl: "https://hermes.example.com",
        hasAuthHeader: true,
        verifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
    )
}
