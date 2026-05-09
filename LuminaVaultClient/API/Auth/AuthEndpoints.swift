// LuminaVaultClient/LuminaVaultClient/API/Auth/AuthEndpoints.swift
import Foundation

enum AuthEndpoints {
    struct Login: Endpoint {
        typealias Response = AuthResponse
        let email: String; let password: String
        var path: String { "/auth/login" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? { LoginRequest(email: email, password: password) }
    }
    struct Register: Endpoint {
        typealias Response = AuthResponse
        let name: String; let email: String; let password: String
        var path: String { "/auth/register" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? { RegisterRequest(name: name, email: email, password: password) }
    }
    struct ForgotPassword: Endpoint {
        typealias Response = EmptyResponse
        let email: String
        var path: String { "/auth/forgot-password" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? { ForgotPasswordRequest(email: email) }
    }
    struct VerifyOTP: Endpoint {
        typealias Response = EmptyResponse
        let email: String; let code: String
        var path: String { "/auth/verify-otp" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? { VerifyOTPRequest(email: email, code: code) }
    }
    struct ResetPassword: Endpoint {
        typealias Response = EmptyResponse
        let token: String; let newPassword: String
        var path: String { "/auth/reset-password" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? { ResetPasswordRequest(token: token, newPassword: newPassword) }
    }
    struct VerifyMFA: Endpoint {
        typealias Response = AuthResponse
        let code: String; let mfaMethod: MFAMethod
        var path: String { "/auth/mfa/verify" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? { MFAVerifyRequest(code: code, mfaMethod: mfaMethod) }
    }
    struct SSOLogin: Endpoint {
        typealias Response = AuthResponse
        let provider: String; let identityToken: String
        var path: String { "/auth/sso/\(provider)" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? { SSORequest(identityToken: identityToken, provider: provider) }
    }
    struct RefreshToken: Endpoint {
        typealias Response = AuthResponse
        let token: String
        var path: String { "/auth/refresh" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? { RefreshRequest(refreshToken: token) }
    }
}
