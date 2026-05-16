// LuminaVaultClient/LuminaVaultClientTests/PhoneAuthViewModelTests.swift
// HER-141: behaviour tests for phone OTP flow on AuthViewModel.
import XCTest
import Foundation
@testable import LuminaVaultClient

@MainActor
final class PhoneAuthViewModelTests: XCTestCase {
    var mockClient: MockAuthClient!
    var appState: AppState!
    var sut: AuthViewModel!

    override func setUp() {
        super.setUp()
        mockClient = MockAuthClient()
        let keychain = KeychainService(service: "com.luminavault.phonetest")
        keychain.clearAll()
        appState = AppState(keychain: keychain)
        sut = AuthViewModel(authClient: mockClient, appState: appState)
        sut.phoneCountry = Countries.all.first { $0.isoCode == "US" }!
    }

    func test_startPhoneOTP_validNumber_transitionsToCodeStep() async {
        mockClient.phoneStartResult = .success(.stub)
        sut.phoneInput = "415 555 0132"
        await sut.startPhoneOTP()

        XCTAssertEqual(sut.phoneStep, .code)
        XCTAssertEqual(sut.phoneE164, "+14155550132")
        XCTAssertEqual(mockClient.phoneStartCalls, ["+14155550132"])
        XCTAssertNil(sut.error)
        XCTAssertGreaterThan(sut.phoneResendSecondsLeft, 0)
    }

    func test_startPhoneOTP_invalidNumber_setsErrorAndDoesNotCallNetwork() async {
        sut.phoneInput = "abc"
        await sut.startPhoneOTP()

        XCTAssertEqual(sut.phoneStep, .entry)
        XCTAssertEqual(mockClient.phoneStartCalls.count, 0)
        XCTAssertEqual(sut.error, "Enter a valid phone number")
    }

    func test_startPhoneOTP_emptyNumber_setsError() async {
        sut.phoneInput = "   "
        await sut.startPhoneOTP()

        XCTAssertEqual(mockClient.phoneStartCalls.count, 0)
        XCTAssertEqual(sut.error, "Enter a valid phone number")
    }

    func test_verifyPhoneOTP_success_authenticatesAppState() async {
        sut.phoneE164 = "+14155550132"
        sut.phoneOtpCode = "123456"
        mockClient.phoneVerifyResult = .success(.stub)

        await sut.verifyPhoneOTP()

        XCTAssertTrue(appState.isAuthenticated)
        XCTAssertNil(sut.error)
        XCTAssertEqual(sut.phoneStep, .entry, "state should reset after auth success")
    }

    func test_verifyPhoneOTP_unauthorized_surfacesInvalidCodeCopy() async {
        sut.phoneE164 = "+14155550132"
        sut.phoneOtpCode = "000000"
        mockClient.phoneVerifyResult = .failure(APIError.unauthorized)

        await sut.verifyPhoneOTP()

        XCTAssertEqual(sut.error, "Invalid code. Try again.")
        XCTAssertFalse(appState.isAuthenticated)
    }

    func test_verifyPhoneOTP_410_surfacesExpiredCopy() async {
        sut.phoneE164 = "+14155550132"
        sut.phoneOtpCode = "123456"
        mockClient.phoneVerifyResult = .failure(APIError.httpError(statusCode: 410, data: Data()))

        await sut.verifyPhoneOTP()

        XCTAssertEqual(sut.error, "Code expired — request a new one.")
    }

    func test_verifyPhoneOTP_429_surfacesRateLimitCopy() async {
        sut.phoneE164 = "+14155550132"
        sut.phoneOtpCode = "123456"
        mockClient.phoneVerifyResult = .failure(APIError.httpError(statusCode: 429, data: Data()))

        await sut.verifyPhoneOTP()

        XCTAssertEqual(sut.error, "Too many attempts — try again later.")
    }

    func test_verifyPhoneOTP_withoutE164_setsError() async {
        sut.phoneE164 = ""
        sut.phoneOtpCode = "123456"

        await sut.verifyPhoneOTP()

        XCTAssertEqual(sut.error, "Send a code first")
        XCTAssertEqual(mockClient.phoneVerifyCalls.count, 0)
    }

    func test_resendPhoneOTP_duringCooldown_isNoOp() async {
        sut.phoneInput = "415 555 0132"
        sut.phoneResendSecondsLeft = 30

        await sut.resendPhoneOTP()

        XCTAssertEqual(mockClient.phoneStartCalls.count, 0,
                       "resend must be blocked while cooldown is active")
    }

    func test_resendPhoneOTP_afterCooldown_replaysStart() async {
        mockClient.phoneStartResult = .success(.stub)
        sut.phoneInput = "415 555 0132"
        sut.phoneResendSecondsLeft = 0

        await sut.resendPhoneOTP()

        XCTAssertEqual(mockClient.phoneStartCalls, ["+14155550132"])
    }
}
