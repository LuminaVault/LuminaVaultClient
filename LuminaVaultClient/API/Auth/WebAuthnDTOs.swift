// LuminaVaultClient/LuminaVaultClient/API/Auth/WebAuthnDTOs.swift
//
// HER-216 — passkey wire-format DTOs.
//
// Temporary inline definitions to unblock client work before
// `LuminaVaultShared` is tagged with the matching types (>= 0.30.0).
// Once the shared bump lands, delete this file and replace each
// declaration with a typealias to the `LuminaVaultShared` original.

import Foundation
import LuminaVaultShared

// MARK: - Begin / Finish registration

struct WebAuthnBeginRegistrationRequest: Codable, Sendable {
    let username: String
    let displayName: String?
}

/// Server response wrapping the raw `PublicKeyCredentialCreationOptions`
/// JSON. `options` is passed through opaquely (no typed mirror of every
/// WebAuthn spec field) — `PasskeyService` decodes only what it needs to
/// drive `ASAuthorizationPlatformPublicKeyCredentialProvider`.
struct WebAuthnBeginRegistrationResponse: Codable, Sendable {
    let options: AnyJSONValue
}

struct WebAuthnAttestationResponseDTO: Codable, Sendable {
    let attestationObject: String // base64url
    let clientDataJSON: String    // base64url
}

struct WebAuthnRegistrationCredentialDTO: Codable, Sendable {
    let id: String       // base64url credential ID
    let rawId: String    // base64url credential ID (raw bytes)
    let type: String     // "public-key"
    let response: WebAuthnAttestationResponseDTO
}

struct WebAuthnFinishRegistrationRequest: Codable, Sendable {
    let username: String
    let credentialCreationData: WebAuthnRegistrationCredentialDTO
}

struct WebAuthnFinishRegistrationResponse: Codable, Sendable {
    let credentialID: String
}

// MARK: - Begin / Finish authentication

struct WebAuthnBeginAuthenticationRequest: Codable, Sendable {
    let username: String
}

struct WebAuthnBeginAuthenticationResponse: Codable, Sendable {
    let options: AnyJSONValue
}

struct WebAuthnAssertionResponseDTO: Codable, Sendable {
    let authenticatorData: String // base64url
    let clientDataJSON: String    // base64url
    let signature: String         // base64url
    let userHandle: String?       // base64url, optional
}

struct WebAuthnAuthenticationCredentialDTO: Codable, Sendable {
    let id: String
    let rawId: String
    let type: String
    let response: WebAuthnAssertionResponseDTO
}

struct WebAuthnFinishAuthenticationRequest: Codable, Sendable {
    let username: String
    let credential: WebAuthnAuthenticationCredentialDTO
}

// MARK: - Settings — list / revoke

struct WebAuthnCredentialSummaryDTO: Codable, Sendable, Identifiable {
    let id: String       // base64url credential ID
    let createdAt: Date
    let lastUsedAt: Date?
    let nickname: String?
}

struct WebAuthnCredentialListResponse: Codable, Sendable {
    let credentials: [WebAuthnCredentialSummaryDTO]
}
