// LuminaVaultClient/LuminaVaultClient/API/Auth/AuthModels.swift
// HER-213: DTOs sourced from LuminaVaultShared; typealiases keep callsites
// unchanged. Shared is the wire-format source of truth — do not redeclare
// any of these types locally.
import Foundation
@_exported import LuminaVaultShared

typealias LoginRequest = LuminaVaultShared.LoginRequest
typealias RegisterRequest = LuminaVaultShared.RegisterRequest
typealias ForgotPasswordRequest = LuminaVaultShared.ForgotPasswordRequest
typealias ResetPasswordRequest = LuminaVaultShared.ResetPasswordRequest
typealias MFAVerifyRequest = LuminaVaultShared.MFAVerifyRequest
typealias OAuthExchangeRequest = LuminaVaultShared.OAuthExchangeRequest
typealias OAuthAccessTokenRequest = LuminaVaultShared.OAuthAccessTokenRequest
typealias RefreshRequest = LuminaVaultShared.RefreshRequest
typealias AuthResponse = LuminaVaultShared.AuthResponse
typealias PhoneStartRequest = LuminaVaultShared.PhoneStartRequest
typealias PhoneStartResponse = LuminaVaultShared.PhoneStartResponse
typealias PhoneVerifyRequest = LuminaVaultShared.PhoneVerifyRequest
typealias EmailMagicStartRequest = LuminaVaultShared.EmailMagicStartRequest
typealias EmailMagicStartResponse = LuminaVaultShared.EmailMagicStartResponse
typealias EmailMagicVerifyRequest = LuminaVaultShared.EmailMagicVerifyRequest
typealias EmptyResponse = LuminaVaultShared.EmptyResponse
typealias MeResponse = LuminaVaultShared.MeResponse
typealias UpdatePrivacyRequest = LuminaVaultShared.UpdatePrivacyRequest
