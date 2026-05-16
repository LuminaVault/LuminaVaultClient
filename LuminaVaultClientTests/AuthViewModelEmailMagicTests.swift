// LuminaVaultClient/LuminaVaultClientTests/AuthViewModelEmailMagicTests.swift
import XCTest
import Foundation
@testable import LuminaVaultClient

@MainActor
final class AuthViewModelEmailMagicTests: XCTestCase {
    var mockClient: MockAuthClient!
    var appState: AppState!
    var sut: AuthViewModel!

    override func setUp() {
        super.setUp()
        mockClient = MockAuthClient()
        let keychain = KeychainService(service: "com.luminavault.emailmagictest")
        keychain.clearAll()
        appState = AppState(keychain: keychain)
        sut = AuthViewModel(authClient: mockClient, appState: appState)
    }

    // MARK: - Start

    func testStartHappyPathAdvancesToVerifyAndCapturesChallenge() async {
        mockClient.emailMagicStartResult = .success(.stub)
        sut.emailMagicEmail = "ada@example.com"
        await sut.startEmailMagic()
        XCTAssertEqual(sut.emailMagicStep, .verify)
        XCTAssertEqual(sut.emailMagicChallengeId, UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        XCTAssertEqual(mockClient.emailMagicStartCalls, ["ada@example.com"])
        XCTAssertEqual(sut.emailMagicResendSecondsLeft, 60)
        XCTAssertNil(sut.error)
    }

    func testStartEmptyEmailSurfacesError() async {
        sut.emailMagicEmail = "   "
        await sut.startEmailMagic()
        XCTAssertEqual(sut.emailMagicStep, .email)
        XCTAssertNotNil(sut.error)
        XCTAssertEqual(mockClient.emailMagicStartCalls.count, 0)
    }

    func testStartErrorSurfacesMessage() async {
        mockClient.emailMagicStartResult = .failure(APIError.httpError(statusCode: 429, data: Data()))
        sut.emailMagicEmail = "ada@example.com"
        await sut.startEmailMagic()
        XCTAssertEqual(sut.emailMagicStep, .email)
        XCTAssertNotNil(sut.error)
        XCTAssertFalse(appState.isAuthenticated)
    }

    // MARK: - Verify

    func testVerifyHappyPathAuthenticates() async {
        mockClient.emailMagicVerifyResult = .success(.stub)
        sut.emailMagicEmail = "ada@example.com"
        sut.emailMagicCode = "123456"
        await sut.verifyEmailMagicCode()
        XCTAssertTrue(appState.isAuthenticated)
        XCTAssertNil(sut.error)
        let recorded = mockClient.emailMagicVerifyCalls.first
        XCTAssertEqual(recorded?.email, "ada@example.com")
        XCTAssertEqual(recorded?.code, "123456")
        // resetEmailMagicState should have cleared transient fields.
        XCTAssertEqual(sut.emailMagicStep, .email)
        XCTAssertEqual(sut.emailMagicEmail, "")
        XCTAssertEqual(sut.emailMagicCode, "")
    }

    func testVerifyEmptyCodeSurfacesError() async {
        sut.emailMagicEmail = "ada@example.com"
        sut.emailMagicCode = ""
        await sut.verifyEmailMagicCode()
        XCTAssertFalse(appState.isAuthenticated)
        XCTAssertNotNil(sut.error)
        XCTAssertEqual(mockClient.emailMagicVerifyCalls.count, 0)
    }

    func testVerifyInvalidCodeMapsToInlineCopy() async {
        mockClient.emailMagicVerifyResult = .failure(APIError.unauthorized)
        sut.emailMagicEmail = "ada@example.com"
        sut.emailMagicCode = "000000"
        await sut.verifyEmailMagicCode()
        XCTAssertFalse(appState.isAuthenticated)
        XCTAssertEqual(sut.error, "Invalid code. Try again.")
    }

    // MARK: - Resend cooldown

    func testResendDuringCooldownIsNoOp() async {
        sut.emailMagicEmail = "ada@example.com"
        sut.emailMagicResendSecondsLeft = 42
        await sut.resendEmailMagic()
        XCTAssertEqual(mockClient.emailMagicStartCalls.count, 0)
    }

    func testResendAfterCooldownRefiresStart() async {
        mockClient.emailMagicStartResult = .success(.stub)
        sut.emailMagicEmail = "ada@example.com"
        sut.emailMagicStep = .verify
        sut.emailMagicResendSecondsLeft = 0
        await sut.resendEmailMagic()
        XCTAssertEqual(mockClient.emailMagicStartCalls.count, 1)
        XCTAssertEqual(sut.emailMagicStep, .verify)
        XCTAssertEqual(sut.emailMagicResendSecondsLeft, 60)
    }
}
