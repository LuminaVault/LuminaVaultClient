// HermesVaultClient/HermesVaultClient/API/Auth/AuthClientProtocol.swift
protocol AuthClientProtocol {
    func login(email: String, password: String) async throws -> AuthResponse
    func register(name: String, email: String, password: String) async throws -> AuthResponse
    func forgotPassword(email: String) async throws
    func verifyOTP(email: String, code: String) async throws
    func resetPassword(token: String, newPassword: String) async throws
    func verifyMFA(code: String, mfaMethod: MFAMethod) async throws -> AuthResponse
    func ssoLogin(provider: String, identityToken: String) async throws -> AuthResponse
    func refreshToken(_ token: String) async throws -> AuthResponse
}
