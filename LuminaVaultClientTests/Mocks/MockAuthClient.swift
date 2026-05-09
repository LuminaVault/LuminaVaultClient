// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockAuthClient.swift
@testable import LuminaVaultClient

final class MockAuthClient: AuthClientProtocol {
    var loginResult: Result<AuthResponse, Error> = .success(.stub)
    var registerResult: Result<AuthResponse, Error> = .success(.stub)
    var forgotPasswordError: Error? = nil
    var verifyOTPError: Error? = nil
    var resetPasswordError: Error? = nil
    var verifyMFAResult: Result<AuthResponse, Error> = .success(.stub)
    var ssoResult: Result<AuthResponse, Error> = .success(.stub)
    var refreshResult: Result<AuthResponse, Error> = .success(.stub)

    func login(email: String, password: String) async throws -> AuthResponse {
        try loginResult.get()
    }
    func register(name: String, email: String, password: String) async throws -> AuthResponse {
        try registerResult.get()
    }
    func forgotPassword(email: String) async throws {
        if let e = forgotPasswordError { throw e }
    }
    func verifyOTP(email: String, code: String) async throws {
        if let e = verifyOTPError { throw e }
    }
    func resetPassword(token: String, newPassword: String) async throws {
        if let e = resetPasswordError { throw e }
    }
    func verifyMFA(code: String, mfaMethod: MFAMethod) async throws -> AuthResponse {
        try verifyMFAResult.get()
    }
    func ssoLogin(provider: String, identityToken: String) async throws -> AuthResponse {
        try ssoResult.get()
    }
    func refreshToken(_ token: String) async throws -> AuthResponse {
        try refreshResult.get()
    }
}

extension AuthResponse {
    static let stub = AuthResponse(
        accessToken: "access-token-stub",
        refreshToken: "refresh-token-stub",
        user: UserDTO(id: "1", name: "Test User", email: "test@example.com", mfaEnabled: false)
    )
    static let stubMFA = AuthResponse(
        accessToken: "access-token-stub",
        refreshToken: "refresh-token-stub",
        user: UserDTO(id: "1", name: "Test User", email: "test@example.com", mfaEnabled: true)
    )
}
