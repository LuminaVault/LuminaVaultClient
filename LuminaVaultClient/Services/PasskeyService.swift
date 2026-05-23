// LuminaVaultClient/LuminaVaultClient/Services/PasskeyService.swift
//
// HER-216 — WebAuthn / passkey driver. Wraps `AuthenticationServices`
// platform-credential APIs and converts between Apple's request/result
// types and the server's `WebAuthn*DTO` wire shape (base64url strings).
//
// Single ownership rule: this is the only file in the client allowed
// to construct `ASAuthorizationController` for passkey flows. Other
// surfaces (AuthLandingView, Settings) call into it via the service
// protocol so flows stay testable and the controller lifecycle is
// scoped to one async call.

import AuthenticationServices
import Foundation
import UIKit

// MARK: - Errors

enum PasskeyError: LocalizedError {
    case unavailable                 // device cannot create / use platform passkeys
    case cancelled                   // user dismissed the system sheet
    case malformedOptions(String)    // server sent options we couldn't parse
    case unsupportedCredentialType   // not an `ASAuthorizationPlatformPublicKeyCredential*`

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Passkeys aren't available on this device."
        case .cancelled: return "Sign-in cancelled."
        case .malformedOptions(let why): return "Server response was malformed: \(why)"
        case .unsupportedCredentialType: return "Unsupported credential type."
        }
    }
}

// MARK: - Protocol

protocol PasskeyServiceProtocol: Sendable {
    /// Drive `ASAuthorizationPlatformPublicKeyCredentialProvider.createCredentialRegistrationRequest`
    /// and return a DTO ready to POST to `/webauthn/register/finish`.
    func register(
        options: AnyJSONValue,
        presentationAnchor: ASPresentationAnchor
    ) async throws -> WebAuthnRegistrationCredentialDTO

    /// Drive `ASAuthorizationPlatformPublicKeyCredentialProvider.createCredentialAssertionRequest`
    /// and return a DTO ready to POST to `/webauthn/authenticate/finish`.
    func authenticate(
        options: AnyJSONValue,
        presentationAnchor: ASPresentationAnchor
    ) async throws -> WebAuthnAuthenticationCredentialDTO
}

// MARK: - Implementation

@MainActor
final class PasskeyService: NSObject, PasskeyServiceProtocol {
    private let relyingPartyIdentifier: String

    /// `relyingPartyIdentifier` MUST match the `id` field returned in the
    /// server's `rp` block (typically the apex domain — e.g. `luminavault.app`).
    /// Mismatches surface as `ASAuthorizationError.failed` at runtime.
    init(relyingPartyIdentifier: String) {
        self.relyingPartyIdentifier = relyingPartyIdentifier
    }

    // MARK: Register

    func register(
        options: AnyJSONValue,
        presentationAnchor: ASPresentationAnchor
    ) async throws -> WebAuthnRegistrationCredentialDTO {
        let parsed = try parseRegistrationOptions(options)
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: parsed.rpID
        )
        let request = provider.createCredentialRegistrationRequest(
            challenge: parsed.challenge,
            name: parsed.userName,
            userID: parsed.userID
        )

        let credential = try await perform(request: request, anchor: presentationAnchor)

        guard let reg = credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
            throw PasskeyError.unsupportedCredentialType
        }
        guard let rawAttestation = reg.rawAttestationObject else {
            throw PasskeyError.unsupportedCredentialType
        }

        return WebAuthnRegistrationCredentialDTO(
            id: reg.credentialID.base64URLEncodedString,
            rawId: reg.credentialID.base64URLEncodedString,
            type: "public-key",
            response: WebAuthnAttestationResponseDTO(
                attestationObject: rawAttestation.base64URLEncodedString,
                clientDataJSON: reg.rawClientDataJSON.base64URLEncodedString
            )
        )
    }

    // MARK: Authenticate

    func authenticate(
        options: AnyJSONValue,
        presentationAnchor: ASPresentationAnchor
    ) async throws -> WebAuthnAuthenticationCredentialDTO {
        let parsed = try parseAuthenticationOptions(options)
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: parsed.rpID
        )
        let request = provider.createCredentialAssertionRequest(challenge: parsed.challenge)
        request.allowedCredentials = parsed.allowedCredentialIDs.map {
            ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
        }

        let credential = try await perform(request: request, anchor: presentationAnchor)

        guard let assertion = credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            throw PasskeyError.unsupportedCredentialType
        }

        return WebAuthnAuthenticationCredentialDTO(
            id: assertion.credentialID.base64URLEncodedString,
            rawId: assertion.credentialID.base64URLEncodedString,
            type: "public-key",
            response: WebAuthnAssertionResponseDTO(
                authenticatorData: assertion.rawAuthenticatorData.base64URLEncodedString,
                clientDataJSON: assertion.rawClientDataJSON.base64URLEncodedString,
                signature: assertion.signature.base64URLEncodedString,
                userHandle: assertion.userID?.base64URLEncodedString
            )
        )
    }

    // MARK: Internal — controller driver

    private func perform(
        request: ASAuthorizationRequest,
        anchor: ASPresentationAnchor
    ) async throws -> ASAuthorizationCredential {
        let controller = ASAuthorizationController(authorizationRequests: [request])
        let delegate = AuthorizationDelegate(anchor: anchor)
        controller.delegate = delegate
        controller.presentationContextProvider = delegate

        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            controller.performRequests()
        }
    }
}

// MARK: - Options parsing

/// Minimal decoded view of the server's WebAuthn registration options
/// blob — only the fields the iOS API actually needs.
private struct ParsedRegistrationOptions {
    let challenge: Data
    let rpID: String
    let userID: Data
    let userName: String
}

private struct ParsedAuthenticationOptions {
    let challenge: Data
    let rpID: String
    let allowedCredentialIDs: [Data]
}

private func parseRegistrationOptions(_ options: AnyJSONValue) throws -> ParsedRegistrationOptions {
    let json = try JSONEncoder().encode(options)
    let dict = try JSONSerialization.jsonObject(with: json) as? [String: Any] ?? [:]

    guard
        let challengeB64 = dict["challenge"] as? String,
        let challenge = Data(base64URLEncoded: challengeB64),
        let rp = dict["rp"] as? [String: Any],
        let rpID = rp["id"] as? String,
        let user = dict["user"] as? [String: Any],
        let userName = user["name"] as? String,
        let userIDB64 = user["id"] as? String,
        let userID = Data(base64URLEncoded: userIDB64)
    else {
        throw PasskeyError.malformedOptions("registration options missing required fields")
    }
    return ParsedRegistrationOptions(
        challenge: challenge,
        rpID: rpID,
        userID: userID,
        userName: userName
    )
}

private func parseAuthenticationOptions(_ options: AnyJSONValue) throws -> ParsedAuthenticationOptions {
    let json = try JSONEncoder().encode(options)
    let dict = try JSONSerialization.jsonObject(with: json) as? [String: Any] ?? [:]

    guard
        let challengeB64 = dict["challenge"] as? String,
        let challenge = Data(base64URLEncoded: challengeB64),
        let rpID = (dict["rpId"] as? String) ?? (dict["rp"] as? [String: Any])?["id"] as? String
    else {
        throw PasskeyError.malformedOptions("authentication options missing required fields")
    }

    let allowed = (dict["allowCredentials"] as? [[String: Any]]) ?? []
    let allowedIDs: [Data] = allowed.compactMap {
        guard let b64 = $0["id"] as? String else { return nil }
        return Data(base64URLEncoded: b64)
    }

    return ParsedAuthenticationOptions(
        challenge: challenge,
        rpID: rpID,
        allowedCredentialIDs: allowedIDs
    )
}

// MARK: - Delegate

@MainActor
private final class AuthorizationDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    var continuation: CheckedContinuation<ASAuthorizationCredential, Error>?

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { anchor }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        MainActor.assumeIsolated {
            continuation?.resume(returning: authorization.credential)
            continuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        MainActor.assumeIsolated {
            let mapped: Error
            if let asError = error as? ASAuthorizationError {
                switch asError.code {
                case .canceled: mapped = PasskeyError.cancelled
                default: mapped = error
                }
            } else {
                mapped = error
            }
            continuation?.resume(throwing: mapped)
            continuation = nil
        }
    }
}

// MARK: - base64url helpers

private extension Data {
    var base64URLEncodedString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = 4 - (s.count % 4)
        if pad < 4 { s += String(repeating: "=", count: pad) }
        guard let d = Data(base64Encoded: s) else { return nil }
        self = d
    }
}
