// LuminaVaultClient/LuminaVaultClient/Services/GoogleSignInService.swift
import Foundation
import AuthenticationServices
import UIKit
import GoogleSignIn

@MainActor
final class GoogleSignInService: SignInServiceProtocol {
    private let clientID: String?

    init(clientID: String? = nil) {
        self.clientID = clientID
            ?? Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
    }

    func signIn(presentationAnchor: ASPresentationAnchor) async throws -> ProviderCredential {
        guard let clientID, !clientID.isEmpty else {
            throw NSError(
                domain: "GoogleSignIn",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Google client ID not configured. Set GIDClientID in Info.plist."]
            )
        }
        if GIDSignIn.sharedInstance.configuration == nil {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        guard let window = presentationAnchor as? UIWindow,
              let root = window.rootViewController else {
            throw NSError(
                domain: "GoogleSignIn",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "No presenting view controller available"]
            )
        }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
            guard let idToken = result.user.idToken?.tokenString else {
                throw NSError(
                    domain: "GoogleSignIn",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Google did not return an idToken"]
                )
            }
            return ProviderCredential(idToken: idToken, rawNonce: nil)
        } catch let err as NSError where err.domain == "com.google.GIDSignIn"
            && err.code == GIDSignInError.Code.canceled.rawValue {
            throw SignInCancelled()
        }
    }
}
