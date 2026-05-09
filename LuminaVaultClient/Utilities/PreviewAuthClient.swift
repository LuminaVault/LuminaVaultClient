// LuminaVaultClient/LuminaVaultClient/Utilities/PreviewAuthClient.swift
import Foundation

final class PreviewAuthClient: AuthClientProtocol {
    private func stub() -> AuthResponse {
        AuthResponse(
            accessToken: "",
            refreshToken: "",
            user: UserDTO(id: "", name: "Preview", email: "preview@example.com", mfaEnabled: false)
        )
    }

    func login(email: String, password: String) async throws -> AuthResponse { stub() }
    func register(name: String, email: String, password: String) async throws -> AuthResponse { stub() }
    func forgotPassword(email: String) async throws {}
    func verifyOTP(email: String, code: String) async throws {}
    func resetPassword(token: String, newPassword: String) async throws {}
    func verifyMFA(code: String, mfaMethod: MFAMethod) async throws -> AuthResponse { stub() }
    func ssoLogin(provider: String, identityToken: String) async throws -> AuthResponse { stub() }
    func refreshToken(_ token: String) async throws -> AuthResponse { stub() }
}
