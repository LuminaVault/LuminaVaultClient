// LuminaVaultClient/LuminaVaultClient/Services/XSignInService.swift
//
// X (Twitter) OAuth 2.0 + PKCE flow via ASWebAuthenticationSession.
// X does not issue an id_token, so we return the access_token in the
// `idToken` slot of ProviderCredential; the server-side XOAuthController
// (per HER-139) treats whatever the client sends as the provider credential
// and exchanges it directly with X's user-info endpoint.
import Foundation
import AuthenticationServices
import CryptoKit

@MainActor
final class XSignInService: NSObject, SignInServiceProtocol {
    private let clientID: String?
    private let redirectURI: String?
    private let scopes: [String]
    private var presentationAnchor: ASPresentationAnchor?
    private let session: URLSession

    init(
        clientID: String? = nil,
        redirectURI: String? = nil,
        scopes: [String] = ["tweet.read", "users.read"],
        session: URLSession = .shared
    ) {
        self.clientID = clientID
            ?? Bundle.main.object(forInfoDictionaryKey: "X_CLIENT_ID") as? String
        self.redirectURI = redirectURI
            ?? Bundle.main.object(forInfoDictionaryKey: "X_REDIRECT_URI") as? String
        self.scopes = scopes
        self.session = session
    }

    func signIn(presentationAnchor: ASPresentationAnchor) async throws -> ProviderCredential {
        guard let clientID, !clientID.isEmpty else {
            throw NSError(domain: "XSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "X client ID not configured (set X_CLIENT_ID in Info.plist)."])
        }
        guard let redirectURI, !redirectURI.isEmpty,
              let redirectURL = URL(string: redirectURI),
              let callbackScheme = redirectURL.scheme else {
            throw NSError(domain: "XSignIn", code: -2, userInfo: [NSLocalizedDescriptionKey: "X redirect URI not configured (set X_REDIRECT_URI in Info.plist)."])
        }
        self.presentationAnchor = presentationAnchor

        let codeVerifier = Self.codeVerifier()
        let codeChallenge = Self.codeChallenge(for: codeVerifier)
        let state = UUID().uuidString

        let authURL = try Self.authorizeURL(
            clientID: clientID,
            redirectURI: redirectURI,
            scopes: scopes,
            state: state,
            codeChallenge: codeChallenge
        )

        let callbackURL: URL = try await withCheckedThrowingContinuation { cont in
            let webSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { url, error in
                if let error {
                    let nsErr = error as NSError
                    if nsErr.domain == ASWebAuthenticationSessionError.errorDomain
                        && nsErr.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        cont.resume(throwing: SignInCancelled())
                    } else {
                        cont.resume(throwing: error)
                    }
                    return
                }
                guard let url else {
                    cont.resume(throwing: NSError(domain: "XSignIn", code: -3, userInfo: [NSLocalizedDescriptionKey: "X returned no callback URL"]))
                    return
                }
                cont.resume(returning: url)
            }
            webSession.presentationContextProvider = self
            webSession.prefersEphemeralWebBrowserSession = false
            webSession.start()
        }

        guard let code = Self.queryItem(callbackURL, "code") else {
            throw NSError(domain: "XSignIn", code: -4, userInfo: [NSLocalizedDescriptionKey: "X callback missing authorization code"])
        }
        if let returnedState = Self.queryItem(callbackURL, "state"), returnedState != state {
            throw NSError(domain: "XSignIn", code: -5, userInfo: [NSLocalizedDescriptionKey: "X callback state mismatch"])
        }

        let accessToken = try await exchangeCodeForAccessToken(
            code: code,
            codeVerifier: codeVerifier,
            clientID: clientID,
            redirectURI: redirectURI
        )
        return ProviderCredential(idToken: accessToken, rawNonce: nil)
    }

    // MARK: - URL construction

    private static func authorizeURL(
        clientID: String,
        redirectURI: String,
        scopes: [String],
        state: String,
        codeChallenge: String
    ) throws -> URL {
        var components = URLComponents(string: "https://twitter.com/i/oauth2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = components.url else {
            throw NSError(domain: "XSignIn", code: -6, userInfo: [NSLocalizedDescriptionKey: "Failed to build X authorize URL"])
        }
        return url
    }

    private func exchangeCodeForAccessToken(
        code: String,
        codeVerifier: String,
        clientID: String,
        redirectURI: String
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.twitter.com/2/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form: [String: String] = [
            "code": code,
            "grant_type": "authorization_code",
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier,
        ]
        request.httpBody = form
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "XSignIn", code: -7, userInfo: [NSLocalizedDescriptionKey: "X token exchange failed: \(body)"])
        }
        struct TokenResponse: Decodable { let access_token: String }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return decoded.access_token
    }

    // MARK: - PKCE

    private static func codeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }

    private static func queryItem(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }

    private static func formEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
}

extension XSignInService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            presentationAnchor ?? ASPresentationAnchor()
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
