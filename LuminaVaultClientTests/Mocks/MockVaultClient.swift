// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockVaultClient.swift
// HER-35 — scripted VaultClientProtocol fake for CreateVaultViewModel tests.

@testable import LuminaVaultClient
import Foundation

final class MockVaultClient: VaultClientProtocol, @unchecked Sendable {
    var createResult: Result<VaultStatusResponse, Error> = .success(
        VaultStatusResponse(initialized: true, createdAt: Date(timeIntervalSince1970: 0), defaultSpaceSlugs: ["ai", "stocks", "health", "work", "ideas"])
    )
    var statusResult: Result<VaultStatusResponse, Error> = .success(
        VaultStatusResponse(initialized: false)
    )

    private(set) var calls: [Call] = []
    enum Call: Equatable {
        case create
        case status
    }

    func createVault() async throws -> VaultStatusResponse {
        calls.append(.create)
        return try createResult.get()
    }

    func status() async throws -> VaultStatusResponse {
        calls.append(.status)
        return try statusResult.get()
    }
}
