// LuminaVaultClient/LuminaVaultClientTests/AuthViewModelTests.swift
import XCTest
import Foundation
@testable import LuminaVaultClient

@MainActor
final class AuthViewModelTests: XCTestCase {
    var mockClient: MockAuthClient!
    var appState: AppState!
    var sut: AuthViewModel!

    override func setUp() {
        super.setUp()
        mockClient = MockAuthClient()
        let keychain = KeychainService(service: "com.luminavault.vmtest")
        keychain.clearAll()
        appState = AppState(keychain: keychain)
        sut = AuthViewModel(authClient: mockClient, appState: appState)
    }

    func testSignInSuccessAuthenticatesAppState() async {
        mockClient.loginResult = .success(.stub)
        sut.email = "a@b.com"; sut.password = "pass"
        await sut.signIn()
        XCTAssertTrue(appState.isAuthenticated)
        XCTAssertNil(sut.error)
    }

    func testSignInFailureSetsError() async {
        mockClient.loginResult = .failure(APIError.unauthorized)
        sut.email = "a@b.com"; sut.password = "wrong"
        await sut.signIn()
        XCTAssertFalse(appState.isAuthenticated)
        XCTAssertNotNil(sut.error)
    }

    func testSignInWithMFASetsMFARequiredAndCapturesChallenge() async {
        mockClient.loginResult = .success(.stubMFA)
        sut.email = "a@b.com"; sut.password = "pass"
        await sut.signIn()
        XCTAssertTrue(sut.mfaRequired)
        XCTAssertEqual(sut.mfaChallengeId, UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        XCTAssertFalse(appState.isAuthenticated)
    }

    func testSignUpMismatchedPasswordsSetsError() async {
        sut.username = "alice"; sut.email = "a@b.com"
        sut.password = "abc"; sut.confirmPassword = "xyz"
        await sut.signUp()
        XCTAssertEqual(sut.error, "Passwords do not match")
        XCTAssertFalse(appState.isAuthenticated)
    }

    func testForgotPasswordAdvancesStep() async {
        mockClient.forgotPasswordError = nil
        sut.forgotEmail = "a@b.com"
        await sut.sendResetCode()
        XCTAssertEqual(sut.forgotStep, 2)
    }

    func testVerifyResetCodeLocallyAdvances() async {
        sut.otpCode = "123456"
        await sut.verifyResetCode()
        XCTAssertEqual(sut.forgotStep, 3)
        XCTAssertNil(sut.error)
    }

    func testVerifyResetCodeRejectsEmpty() async {
        sut.otpCode = ""
        await sut.verifyResetCode()
        XCTAssertEqual(sut.forgotStep, 1)
        XCTAssertNotNil(sut.error)
    }

    func testVerifyMFAAuthenticates() async {
        mockClient.verifyMFAResult = .success(.stub)
        sut.mfaChallengeId = UUID()
        sut.mfaCode = "123456"
        await sut.verifyMFA()
        XCTAssertTrue(appState.isAuthenticated)
    }

    func testVerifyMFAWithoutChallengeIdSetsError() async {
        sut.mfaChallengeId = nil
        sut.mfaCode = "123456"
        await sut.verifyMFA()
        XCTAssertFalse(appState.isAuthenticated)
        XCTAssertNotNil(sut.error)
    }
}
