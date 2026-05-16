// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockAuthClient.swift
import Foundation
@testable import LuminaVaultClient

final class MockAuthClient: AuthClientProtocol {
    var loginResult: Result<AuthResponse, Error> = .success(.stub)
    var registerResult: Result<AuthResponse, Error> = .success(.stub)
    var forgotPasswordError: Error? = nil
    var resetPasswordError: Error? = nil
    var verifyMFAResult: Result<AuthResponse, Error> = .success(.stub)
    var exchangeOAuthResult: Result<AuthResponse, Error> = .success(.stub)
    var refreshResult: Result<AuthResponse, Error> = .success(.stub)
    var phoneStartResult: Result<PhoneStartResponse, Error> = .success(.stub)
    var phoneVerifyResult: Result<AuthResponse, Error> = .success(.stub)
    var emailMagicStartResult: Result<EmailMagicStartResponse, Error> = .success(.stub)
    var emailMagicVerifyResult: Result<AuthResponse, Error> = .success(.stub)

    // Invocation recorders
    private(set) var loginCalls: [(email: String, password: String, mfaCode: String?)] = []
    private(set) var exchangeOAuthCalls: [(provider: String, idToken: String)] = []
    private(set) var verifyMFACalls: [(challengeId: UUID, code: String)] = []
    private(set) var phoneStartCalls: [String] = []
    private(set) var phoneVerifyCalls: [(phone: String, code: String)] = []
    private(set) var emailMagicStartCalls: [String] = []
    private(set) var emailMagicVerifyCalls: [(email: String, code: String)] = []

    func login(email: String, password: String, mfaCode: String?) async throws -> AuthResponse {
        loginCalls.append((email, password, mfaCode))
        return try loginResult.get()
    }
    func register(email: String, username: String, password: String) async throws -> AuthResponse {
        try registerResult.get()
    }
    func forgotPassword(email: String) async throws {
        if let e = forgotPasswordError { throw e }
    }
    func resetPassword(email: String, code: String, newPassword: String) async throws {
        if let e = resetPasswordError { throw e }
    }
    func verifyMFA(challengeId: UUID, code: String) async throws -> AuthResponse {
        verifyMFACalls.append((challengeId, code))
        return try verifyMFAResult.get()
    }
    func exchangeOAuth(provider: String, idToken: String) async throws -> AuthResponse {
        exchangeOAuthCalls.append((provider, idToken))
        return try exchangeOAuthResult.get()
    }
    func refreshToken(_ token: String) async throws -> AuthResponse {
        try refreshResult.get()
    }
    func phoneStart(phone: String) async throws -> PhoneStartResponse {
        phoneStartCalls.append(phone)
        return try phoneStartResult.get()
    }
    func phoneVerify(phone: String, code: String) async throws -> AuthResponse {
        phoneVerifyCalls.append((phone, code))
        return try phoneVerifyResult.get()
    }
    func emailMagicStart(email: String) async throws -> EmailMagicStartResponse {
        emailMagicStartCalls.append(email)
        return try emailMagicStartResult.get()
    }
    func emailMagicVerify(email: String, code: String) async throws -> AuthResponse {
        emailMagicVerifyCalls.append((email, code))
        return try emailMagicVerifyResult.get()
    }
}

extension EmailMagicStartResponse {
    static let stub = EmailMagicStartResponse(
        challengeId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        expiresAt: Date().addingTimeInterval(600)
    )
}

extension PhoneStartResponse {
    static let stub = PhoneStartResponse(
        challengeId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        expiresAt: Date().addingTimeInterval(300)
    )
}

extension AuthResponse {
    static let stub = AuthResponse(
        userId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        email: "test@example.com",
        accessToken: "access-token-stub",
        refreshToken: "refresh-token-stub",
        expiresIn: 3600,
        mfaRequired: nil,
        mfaChallengeId: nil
    )
    static let stubMFA = AuthResponse(
        userId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        email: "test@example.com",
        accessToken: "",
        refreshToken: "",
        expiresIn: 0,
        mfaRequired: true,
        mfaChallengeId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    )
}
