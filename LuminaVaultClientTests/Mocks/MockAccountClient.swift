// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockAccountClient.swift
// HER-212 — scripted AccountClientProtocol fake.
@testable import LuminaVaultClient
import Foundation

final class MockAccountClient: AccountClientProtocol, @unchecked Sendable {
    var deleteResult: Result<Void, Error> = .success(())
    private(set) var deleteCalls = 0

    func deleteAccount() async throws {
        deleteCalls += 1
        _ = try deleteResult.get()
    }
}
