// LuminaVaultClient/LuminaVaultClient/API/Auth/AuthModels.swift
import Foundation

struct LoginRequest: Encodable         { let email: String; let password: String }
struct RegisterRequest: Encodable      { let name: String; let email: String; let password: String }
struct ForgotPasswordRequest: Encodable { let email: String }
struct VerifyOTPRequest: Encodable     { let email: String; let code: String }
struct ResetPasswordRequest: Encodable { let token: String; let newPassword: String }
struct SSORequest: Encodable           { let identityToken: String; let provider: String }
struct RefreshRequest: Encodable       { let refreshToken: String }

enum MFAMethod: String, Encodable, CaseIterable { case totp, sms }
struct MFAVerifyRequest: Encodable     { let code: String; let mfaMethod: MFAMethod }

struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let user: UserDTO
}
struct UserDTO: Decodable {
    let id: String
    let name: String
    let email: String
    let mfaEnabled: Bool
}
struct EmptyResponse: Decodable {}
