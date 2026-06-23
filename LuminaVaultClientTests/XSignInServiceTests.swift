// LuminaVaultClient/LuminaVaultClientTests/XSignInServiceTests.swift
//
// HER-144 — covers PKCE generation, authorize URL construction, callback
// parsing, retry-on-bad-redirect, state-mismatch, cancellation, and the
// X token-exchange HTTP call. ASWebAuthenticationSession is faked via the
// `WebAuthSessionDriving` protocol so the suite never opens a real browser.
import XCTest
import AuthenticationServices
import CryptoKit
@testable import LuminaVaultClient

@MainActor
final class XSignInServiceTests: XCTestCase {

    // MARK: - PKCE

    func testCodeVerifierIsBase64URLAndCorrectLength() {
        let v = XSignInService.codeVerifier()
        // 32 bytes → 43-char base64url (no padding).
        XCTAssertEqual(v.count, 43)
        XCTAssertFalse(v.contains("="))
        XCTAssertFalse(v.contains("+"))
        XCTAssertFalse(v.contains("/"))
    }

    func testCodeChallengeMatchesRFC7636Vector() {
        // RFC 7636 §B test vector.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        XCTAssertEqual(XSignInService.codeChallenge(for: verifier), expected)
    }

    // MARK: - Authorize URL builder

    func testAuthorizeURLContainsAllRequiredParams() throws {
        let url = try XSignInService.authorizeURL(
            clientID: "xclient",
            redirectURI: "luminavault-debug://oauth/x/callback",
            scopes: ["tweet.read", "users.read"],
            state: "STATE123",
            codeChallenge: "CHAL456"
        )
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.host, "twitter.com")
        XCTAssertEqual(url.path, "/i/oauth2/authorize")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["client_id"], "xclient")
        XCTAssertEqual(items["redirect_uri"], "luminavault-debug://oauth/x/callback")
        XCTAssertEqual(items["scope"], "tweet.read users.read")
        XCTAssertEqual(items["state"], "STATE123")
        XCTAssertEqual(items["code_challenge"], "CHAL456")
        XCTAssertEqual(items["code_challenge_method"], "S256")
    }

    // MARK: - Callback parsing

    func testQueryItemPullsValueFromCallbackURL() {
        let url = URL(string: "luminavault-debug://oauth/x/callback?code=abc&state=xyz")!
        XCTAssertEqual(XSignInService.queryItem(url, "code"), "abc")
        XCTAssertEqual(XSignInService.queryItem(url, "state"), "xyz")
        XCTAssertNil(XSignInService.queryItem(url, "missing"))
    }

    // MARK: - Sign-in flow integration with stub driver

    func testNotConfiguredWhenClientIDMissing() async {
        let svc = XSignInService(clientID: "", redirectURI: "x://cb", webAuthDriver: NoopWebAuthDriver())
        do {
            _ = try await svc.signIn(presentationAnchor: ASPresentationAnchor())
            XCTFail("expected throw")
        } catch let err as XSignInError {
            if case .notConfigured = err { } else { XCTFail("unexpected case \(err)") }
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testStateMismatchThrowsXSignInError() async {
        let driver = StubWebAuthDriver(responder: { url in
            // X returns a different `state` than what we sent.
            return URL(string: "x://cb?code=abc&state=tampered")!
        })
        let svc = makeService(driver: driver, urlSessionData: tokenSuccessData(token: "tok"))
        do {
            _ = try await svc.signIn(presentationAnchor: ASPresentationAnchor())
            XCTFail("expected throw")
        } catch XSignInError.stateMismatch {
            // ok
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testMissingStateThrowsXSignInError() async {
        let driver = StubWebAuthDriver(responder: { _ in
            URL(string: "x://cb?code=abc")!
        })
        let svc = makeService(driver: driver, urlSessionData: tokenSuccessData(token: "tok"))
        do {
            _ = try await svc.signIn(presentationAnchor: ASPresentationAnchor())
            XCTFail("expected throw")
        } catch XSignInError.stateMismatch {
            // ok
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testCancellationPropagatesAsSignInCancelled() async {
        let driver = StubWebAuthDriver(responder: { _ in throw SignInCancelled() })
        let svc = makeService(driver: driver, urlSessionData: Data())
        do {
            _ = try await svc.signIn(presentationAnchor: ASPresentationAnchor())
            XCTFail("expected throw")
        } catch is SignInCancelled {
            // ok
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testMissingCodeRetriesOnceThenSucceeds() async throws {
        var attempt = 0
        let driver = StubWebAuthDriver(responder: { _ in
            attempt += 1
            if attempt == 1 {
                return URL(string: "x://cb?state=STATE")!  // missing code → badRedirect
            }
            let state = XSignInService.queryItem(url, "state")!
            return URL(string: "x://cb?code=goodcode&state=\(state)")!
        })
        // Inject capturing URLSession; on the retry path the token exchange runs.
        let svc = makeService(driver: driver, urlSessionData: tokenSuccessData(token: "TOK"))
        let cred = try await svc.signIn(presentationAnchor: ASPresentationAnchor())
        XCTAssertEqual(attempt, 2)
        XCTAssertEqual(cred.idToken, "TOK")
        XCTAssertEqual(cred.tokenKind, .accessToken)
    }

    func testMissingCodeOnBothAttemptsThrowsBadRedirect() async {
        let driver = StubWebAuthDriver(responder: { _ in URL(string: "x://cb?state=STATE")! })
        let svc = makeService(driver: driver, urlSessionData: Data())
        do {
            _ = try await svc.signIn(presentationAnchor: ASPresentationAnchor())
            XCTFail("expected throw")
        } catch XSignInError.badRedirect {
            // ok
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testTokenExchangeNon2xxThrowsInvalidGrant() async {
        let driver = StubWebAuthDriver(responder: { url in
            let state = XSignInService.queryItem(url, "state")!
            return URL(string: "x://cb?code=abc&state=\(state)")!
        })
        URLProtocolStub.handler = { _ in
            let body = #"{"error":"invalid_grant","error_description":"bad pkce"}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: URL(string: "https://api.twitter.com/2/oauth2/token")!,
                                    statusCode: 400, httpVersion: nil, headerFields: nil)!,
                    body)
        }
        let svc = XSignInService(
            clientID: "xclient",
            redirectURI: "x://cb",
            scopes: ["s"],
            session: URLProtocolStub.session(),
            webAuthDriver: driver
        )
        do {
            _ = try await svc.signIn(presentationAnchor: ASPresentationAnchor())
            XCTFail("expected throw")
        } catch XSignInError.invalidGrant(let msg) {
            XCTAssertTrue(msg.contains("invalid_grant"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testTokenExchangeNetworkErrorMapsToNetworkCase() async {
        let driver = StubWebAuthDriver(responder: { url in
            let state = XSignInService.queryItem(url, "state")!
            return URL(string: "x://cb?code=abc&state=\(state)")!
        })
        URLProtocolStub.handler = { _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        }
        let svc = XSignInService(
            clientID: "xclient",
            redirectURI: "x://cb",
            scopes: ["s"],
            session: URLProtocolStub.session(),
            webAuthDriver: driver
        )
        do {
            _ = try await svc.signIn(presentationAnchor: ASPresentationAnchor())
            XCTFail("expected throw")
        } catch XSignInError.network {
            // ok
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // MARK: - Helpers

    private func tokenSuccessData(token: String) -> Data {
        #"{"access_token":"\#(token)","token_type":"bearer","expires_in":7200,"scope":"tweet.read users.read"}"#
            .data(using: .utf8)!
    }

    private func makeService(driver: any WebAuthSessionDriving, urlSessionData data: Data) -> XSignInService {
        URLProtocolStub.handler = { _ in
            (HTTPURLResponse(url: URL(string: "https://api.twitter.com/2/oauth2/token")!,
                             statusCode: 200, httpVersion: nil, headerFields: nil)!,
             data)
        }
        return XSignInService(
            clientID: "xclient",
            redirectURI: "x://cb",
            scopes: ["tweet.read"],
            session: URLProtocolStub.session(),
            webAuthDriver: driver
        )
    }
}

// MARK: - Stubs

@MainActor
private final class StubWebAuthDriver: WebAuthSessionDriving {
    private let responder: (URL) throws -> URL
    init(responder: @escaping (URL) throws -> URL) { self.responder = responder }
    func authenticate(url: URL, callbackURLScheme: String, presentationAnchor: ASPresentationAnchor) async throws -> URL {
        try responder(url)
    }
}

@MainActor
private final class NoopWebAuthDriver: WebAuthSessionDriving {
    func authenticate(url: URL, callbackURLScheme: String, presentationAnchor: ASPresentationAnchor) async throws -> URL {
        XCTFail("driver should not be called when client config is missing")
        return URL(string: "about:blank")!
    }
}

// MARK: - URLProtocol stub

final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    nonisolated(unsafe) static var handler: Handler?

    static func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: cfg)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = URLProtocolStub.handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "stub", code: -1))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
