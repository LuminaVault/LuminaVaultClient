// LuminaVaultClient/LuminaVaultClientTests/AuthViewModelTests.swift
import XCTest
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

    func testSignInWithMFASetsMFARequired() async {
        mockClient.loginResult = .success(.stubMFA)
        sut.email = "a@b.com"; sut.password = "pass"
        await sut.signIn()
        XCTAssertTrue(sut.mfaRequired)
        XCTAssertFalse(appState.isAuthenticated)
    }

    func testSignUpMismatchedPasswordsSetsError() async {
        sut.name = "Alice"; sut.email = "a@b.com"
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

    func testVerifyMFAAuthenticates() async {
        mockClient.verifyMFAResult = .success(.stub)
        sut.mfaCode = "123456"
        await sut.verifyMFA()
        XCTAssertTrue(appState.isAuthenticated)
    }
}
