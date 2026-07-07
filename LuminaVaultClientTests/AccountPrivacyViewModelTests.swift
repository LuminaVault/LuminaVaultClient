// LuminaVaultClient/LuminaVaultClientTests/AccountPrivacyViewModelTests.swift
import XCTest
@testable import LuminaVaultClient

@MainActor
final class AccountPrivacyViewModelTests: XCTestCase {
    func testToggleAutoSaveLinksPersistsAndAppliesReturnedProfile() async {
        let client = MockAuthClient()
        client.getMeResult = .success(.stub)
        client.updatePrivacyResult = .success(MeResponse(
            userId: MeResponse.stub.userId,
            email: MeResponse.stub.email,
            username: MeResponse.stub.username,
            isVerified: true,
            privacyNoCNOrigin: false,
            contextRouting: true,
            autoSaveLinks: false,
            mnemosyneEnabled: true
        ))

        let viewModel = AccountPrivacyViewModel(authClient: client)
        await viewModel.load()
        await viewModel.setAutoSaveLinks(false)

        XCTAssertEqual(client.updatePrivacyCalls.count, 1)
        XCTAssertEqual(client.updatePrivacyCalls.first?.autoSaveLinks, false)
        XCTAssertFalse(viewModel.autoSaveLinks)
        XCTAssertTrue(viewModel.mnemosyneEnabled)
        XCTAssertEqual(viewModel.state, .loaded)
    }
}
