// LuminaVaultClient/LuminaVaultClientTests/DataAccessViewModelTests.swift
import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

@MainActor
final class DataAccessViewModelTests: XCTestCase {
    func testSetAllowedRollsBackAndShowsFailureWhenServerRejectsUpdate() async {
        let client = MockAppleConsentClient()
        client.getResult = .success(AppleConsentResponse(consents: [
            AppleConsentDTO(domain: .health, allowed: false, allowWrites: false)
        ]))
        client.updateResult = .failure(APIError.unauthorized)
        let updateAttempted = expectation(description: "update attempted")
        client.onUpdate = { updateAttempted.fulfill() }

        let viewModel = DataAccessViewModel(client: client)
        await viewModel.load()
        viewModel.setAllowed(.health, true)

        await fulfillment(of: [updateAttempted], timeout: 1.0)
        await Task.yield()

        XCTAssertFalse(viewModel.consent(.health).allowed)
        XCTAssertEqual(viewModel.state, .failed("Session expired — sign in again."))
    }
}

private final class MockAppleConsentClient: AppleConsentClientProtocol, @unchecked Sendable {
    var getResult: Result<AppleConsentResponse, Error> = .success(.init(consents: []))
    var updateResult: Result<AppleConsentResponse, Error> = .success(.init(consents: []))
    var onUpdate: (() -> Void)?
    private(set) var updates: [AppleConsentUpdateRequest] = []

    func get() async throws -> AppleConsentResponse {
        try getResult.get()
    }

    func update(_ request: AppleConsentUpdateRequest) async throws -> AppleConsentResponse {
        updates.append(request)
        onUpdate?()
        return try updateResult.get()
    }
}
