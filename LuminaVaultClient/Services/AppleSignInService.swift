// LuminaVaultClient/LuminaVaultClient/Services/AppleSignInService.swift
import Foundation
import AuthenticationServices
import CryptoKit

@MainActor
final class AppleSignInService: NSObject, SignInServiceProtocol {
    private var continuation: CheckedContinuation<ProviderCredential, Error>?
    private var currentRawNonce: String?
    private var presentationAnchor: ASPresentationAnchor?
    // ASAuthorizationController.delegate and .presentationContextProvider are
    // BOTH weak. If the controller is only a local var it deallocates the
    // instant `signIn` suspends at the continuation — the system sheet never
    // presents and no delegate callback ever fires ("Sign in with Apple does
    // nothing"). Hold a strong reference until the flow resolves.
    private var controller: ASAuthorizationController?

    func signIn(presentationAnchor: ASPresentationAnchor) async throws -> ProviderCredential {
        let rawNonce = Self.randomNonceString()
        currentRawNonce = rawNonce
        self.presentationAnchor = presentationAnchor

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(rawNonce)

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    // MARK: Nonce

    private static func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

extension AppleSignInService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                continuation?.resume(throwing: NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing identity token from Apple"]))
                continuation = nil
                self.controller = nil
                return
            }
            continuation?.resume(returning: ProviderCredential(
                idToken: idToken,
                rawNonce: currentRawNonce,
                appleUserID: credential.user,
                fullName: credential.fullName
            ))
            continuation = nil
            currentRawNonce = nil
            self.controller = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            let nsErr = error as NSError
            if nsErr.domain == ASAuthorizationErrorDomain,
               let code = ASAuthorizationError.Code(rawValue: nsErr.code),
               code == .canceled {
                continuation?.resume(throwing: SignInCancelled())
            } else {
                continuation?.resume(throwing: error)
            }
            continuation = nil
            currentRawNonce = nil
            self.controller = nil
        }
    }
}

extension AppleSignInService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            presentationAnchor ?? ASPresentationAnchor()
        }
    }
}
