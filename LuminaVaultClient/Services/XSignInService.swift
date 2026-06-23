// LuminaVaultClient/LuminaVaultClient/Services/XSignInService.swift
//
// HER-144 — X (Twitter) OAuth 2.0 + PKCE via ASWebAuthenticationSession.
// X has no native iOS SDK and does not issue id_tokens, so the client runs
// the full authorize → code → token-exchange dance and forwards the bearer
// access_token to the server's `/v1/auth/oauth/x/exchange` route (decoded
// as `{ accessToken }`). `ProviderCredential.tokenKind = .accessToken`
// tells AuthViewModel to take the access-token exchange path.
import Foundation
import AuthenticationServices
import CryptoKit

/// User-facing errors from the X sign-in flow. Each case carries enough
/// context for `errorDescription` to surface a clean banner without leaking
/// HTTP bodies into the UI.
enum XSignInError: LocalizedError {
    case notConfigured(String)
    case badRedirect
    case stateMismatch
    case invalidGrant(String)
    case network(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let detail):
            return "X Sign-In isn't set up on this build (\(detail))."
        case .badRedirect:
            return "X returned an unexpected response. Please try again."
        case .stateMismatch:
            return "X sign-in failed a security check. Please try again."
        case .invalidGrant(let message):
            return message.isEmpty ? "X rejected the sign-in attempt." : message
        case .network:
            return "Couldn't reach X. Check your connection and try again."
        }
    }
}

/// Abstracts `ASWebAuthenticationSession` so tests can swap in a deterministic
/// driver without bringing up real browser UI.
@MainActor
protocol WebAuthSessionDriving {
    func authenticate(
        url: URL,
        callbackURLScheme: String,
        presentationAnchor: ASPresentationAnchor
    ) async throws -> URL
}

@MainActor
final class XSignInService: NSObject, SignInServiceProtocol {
    private let clientID: String?
    private let redirectURI: String?
    private let scopes: [String]
    private var presentationAnchor: ASPresentationAnchor?
    private let session: URLSession
    private let webAuthDriver: any WebAuthSessionDriving

    init(
        clientID: String? = nil,
        redirectURI: String? = nil,
        scopes: [String] = ["tweet.read", "users.read"],
        session: URLSession = .shared,
        webAuthDriver: (any WebAuthSessionDriving)? = nil
    ) {
        self.clientID = clientID
            ?? Bundle.main.object(forInfoDictionaryKey: "X_CLIENT_ID") as? String
        self.redirectURI = redirectURI
            ?? Bundle.main.object(forInfoDictionaryKey: "X_REDIRECT_URI") as? String
        self.scopes = scopes
        self.session = session
        self.webAuthDriver = webAuthDriver ?? ASWebAuthSessionDriver()
    }

    func signIn(presentationAnchor: ASPresentationAnchor) async throws -> ProviderCredential {
        guard let clientID, !clientID.isEmpty else {
            throw XSignInError.notConfigured("set X_CLIENT_ID in Info.plist")
        }
        guard let redirectURI, !redirectURI.isEmpty,
              let redirectURL = URL(string: redirectURI),
              let callbackScheme = redirectURL.scheme else {
            throw XSignInError.notConfigured("set X_REDIRECT_URI in Info.plist")
        }
        self.presentationAnchor = presentationAnchor

        // HER-144 acceptance: retry once on a bad redirect (transient network /
        // browser hiccup) before surfacing the error. Cancellation never retries.
        var lastBadRedirect: Error?
        for attempt in 0..<2 {
            do {
                return try await performAuthorize(
                    clientID: clientID,
                    redirectURI: redirectURI,
                    callbackScheme: callbackScheme,
                    presentationAnchor: presentationAnchor
                )
            } catch XSignInError.badRedirect where attempt == 0 {
                lastBadRedirect = XSignInError.badRedirect
                continue
            }
        }
        throw lastBadRedirect ?? XSignInError.badRedirect
    }

    private func performAuthorize(
        clientID: String,
        redirectURI: String,
        callbackScheme: String,
        presentationAnchor: ASPresentationAnchor
    ) async throws -> ProviderCredential {
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

        let callbackURL = try await webAuthDriver.authenticate(
            url: authURL,
            callbackURLScheme: callbackScheme,
            presentationAnchor: presentationAnchor
        )

        guard let code = Self.queryItem(callbackURL, "code") else {
            throw XSignInError.badRedirect
        }
        guard let returnedState = Self.queryItem(callbackURL, "state"), returnedState == state else {
            throw XSignInError.stateMismatch
        }

        let accessToken = try await exchangeCodeForAccessToken(
            code: code,
            codeVerifier: codeVerifier,
            clientID: clientID,
            redirectURI: redirectURI
        )
        return ProviderCredential(
            idToken: accessToken,
            rawNonce: nil,
            tokenKind: .accessToken
        )
    }

    // MARK: - URL construction

    static func authorizeURL(
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
            throw XSignInError.notConfigured("Failed to build X authorize URL")
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw XSignInError.network(underlying: error)
        }

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = Self.parseTokenErrorMessage(data: data)
            throw XSignInError.invalidGrant(message)
        }
        struct TokenResponse: Decodable { let access_token: String }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data).access_token
        } catch {
            throw XSignInError.invalidGrant("X returned an unreadable token response.")
        }
    }

    private static func parseTokenErrorMessage(data: Data) -> String {
        struct ErrBody: Decodable {
            let error: String?
            let error_description: String?
        }
        if let parsed = try? JSONDecoder().decode(ErrBody.self, from: data) {
            let pieces = [parsed.error, parsed.error_description].compactMap { $0 }
            if !pieces.isEmpty { return pieces.joined(separator: ": ") }
        }
        return ""
    }

    // MARK: - PKCE

    static func codeVerifier(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    static func codeChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }

    static func queryItem(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }

    private static func formEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
}

// MARK: - Default web-auth driver backed by ASWebAuthenticationSession

@MainActor
private final class ASWebAuthSessionDriver: NSObject, WebAuthSessionDriving, ASWebAuthenticationPresentationContextProviding {
    private var anchor: ASPresentationAnchor?
    // ASWebAuthenticationSession must be strongly retained until its completion
    // handler fires — otherwise the system can deallocate it the moment this
    // function suspends, dismissing the browser sheet before the user finishes.
    private var webSession: ASWebAuthenticationSession?

    func authenticate(
        url: URL,
        callbackURLScheme: String,
        presentationAnchor: ASPresentationAnchor
    ) async throws -> URL {
        self.anchor = presentationAnchor
        return try await withCheckedThrowingContinuation { cont in
            let webSession = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackURLScheme) { [weak self] url, error in
                self?.webSession = nil
                if let error {
                    let nsErr = error as NSError
                    if nsErr.domain == ASWebAuthenticationSessionError.errorDomain
                        && nsErr.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        cont.resume(throwing: SignInCancelled())
                    } else {
                        cont.resume(throwing: XSignInError.network(underlying: error))
                    }
                    return
                }
                guard let url else {
                    cont.resume(throwing: XSignInError.badRedirect)
                    return
                }
                cont.resume(returning: url)
            }
            webSession.presentationContextProvider = self
            webSession.prefersEphemeralWebBrowserSession = false
            self.webSession = webSession
            webSession.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            anchor ?? ASPresentationAnchor()
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
