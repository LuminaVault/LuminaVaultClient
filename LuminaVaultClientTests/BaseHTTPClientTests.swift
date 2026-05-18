// LuminaVaultClient/LuminaVaultClientTests/BaseHTTPClientTests.swift
import XCTest
@testable import LuminaVaultClient

final class BaseHTTPClientTests: XCTestCase {
    var client: BaseHTTPClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        client = BaseHTTPClient(
            baseURL: URL(string: "http://test.local")!,
            session: session
        )
    }

    func testExecuteDecodesSuccessResponse() async throws {
        struct PingEndpoint: Endpoint {
            typealias Response = PingResponse
            var path: String { "/ping" }
            var method: HTTPMethod { .get }
            var requiresAuth: Bool { false }
        }
        struct PingResponse: Decodable { let message: String }

        MockURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://test.local/ping")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let data = #"{"message":"pong"}"#.data(using: .utf8)!
            return (response, data)
        }

        let result = try await client.execute(PingEndpoint())
        XCTAssertEqual(result.message, "pong")
    }

    func testExecuteThrowsUnauthorizedOn401() async {
        struct SecureEndpoint: Endpoint {
            typealias Response = EmptyResponse
            var path: String { "/secure" }
            var method: HTTPMethod { .get }
            var requiresAuth: Bool { false }
        }

        MockURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://test.local/secure")!,
                statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        do {
            _ = try await client.execute(SecureEndpoint())
            XCTFail("Expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // pass
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - HER-237: 401 auto-refresh interceptor

    private struct ProtectedEndpoint: Endpoint {
        typealias Response = ProtectedResponse
        var path: String { "/protected" }
        var method: HTTPMethod { .get }
    }
    private struct ProtectedResponse: Decodable { let ok: Bool }

    func testRefreshOnFirst401ThenRetrySucceeds() async throws {
        let attempt = Counter()
        let refreshCalls = Counter()
        MockURLProtocol.handler = { req in
            await attempt.increment()
            let n = await attempt.value
            let auth = req.value(forHTTPHeaderField: "Authorization")
            // First call carries the stale token. Second carries the refreshed one.
            if n == 1 {
                XCTAssertEqual(auth, "Bearer stale")
                let resp = HTTPURLResponse(
                    url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil
                )!
                return (resp, Data())
            } else {
                XCTAssertEqual(auth, "Bearer fresh")
                let resp = HTTPURLResponse(
                    url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!
                return (resp, #"{"ok":true}"#.data(using: .utf8)!)
            }
        }

        let token = TokenStore(access: "stale")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let interceptor = BaseHTTPClient(
            baseURL: URL(string: "http://test.local")!,
            session: session,
            tokenProvider: { await token.access },
            refreshHandler: {
                await refreshCalls.increment()
                await token.set(access: "fresh")
                return "fresh"
            },
            onAuthFailure: { XCTFail("sign-out must not fire on successful refresh") }
        )

        let result = try await interceptor.execute(ProtectedEndpoint())
        XCTAssertTrue(result.ok)
        let refreshCount = await refreshCalls.value
        let attempts = await attempt.value
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(attempts, 2, "Expected one 401 + one 200")
    }

    func testRefreshFailureCallsOnAuthFailureAndThrowsUnauthorized() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (resp, Data())
        }

        let signOutFired = Flag()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let interceptor = BaseHTTPClient(
            baseURL: URL(string: "http://test.local")!,
            session: session,
            tokenProvider: { "stale" },
            refreshHandler: { throw APIError.unauthorized },
            onAuthFailure: { await signOutFired.raise() }
        )

        do {
            _ = try await interceptor.execute(ProtectedEndpoint())
            XCTFail("Expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // pass
        } catch {
            XCTFail("Wrong error: \(error)")
        }
        let fired = await signOutFired.isSet
        XCTAssertTrue(fired, "onAuthFailure should fire when refresh fails")
    }

    func testSkipsAuthRefreshEndpointPropagates401Immediately() async {
        struct LoginLike: Endpoint {
            typealias Response = EmptyResponse
            var path: String { "/v1/auth/login" }
            var method: HTTPMethod { .post }
            var requiresAuth: Bool { false } // default skipsAuthRefresh becomes true
        }

        let refreshCalls = Counter()
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (resp, Data())
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let interceptor = BaseHTTPClient(
            baseURL: URL(string: "http://test.local")!,
            session: session,
            tokenProvider: { nil },
            refreshHandler: {
                await refreshCalls.increment()
                return "should-never-be-called"
            },
            onAuthFailure: { XCTFail("sign-out must not fire on auth-bootstrap 401") }
        )

        do {
            _ = try await interceptor.execute(LoginLike())
            XCTFail("Expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // pass
        } catch {
            XCTFail("Wrong error: \(error)")
        }
        let calls = await refreshCalls.value
        XCTAssertEqual(calls, 0, "skipsAuthRefresh endpoints must bypass refresh")
    }

    func testConcurrent401sShareSingleRefresh() async throws {
        let attempt = Counter()
        let refreshCalls = Counter()
        let baseURL = URL(string: "http://test.local")!
        MockURLProtocol.handler = { req in
            await attempt.increment()
            let auth = req.value(forHTTPHeaderField: "Authorization")
            let code = (auth == "Bearer fresh") ? 200 : 401
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: code, httpVersion: nil, headerFields: nil
            )!
            let body = (code == 200) ? #"{"ok":true}"#.data(using: .utf8)! : Data()
            return (resp, body)
        }

        let token = TokenStore(access: "stale")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let coordinator = TokenRefreshCoordinator()
        let interceptor = BaseHTTPClient(
            baseURL: baseURL,
            session: session,
            tokenProvider: { await token.access },
            refreshHandler: {
                await refreshCalls.increment()
                try await Task.sleep(nanoseconds: 50_000_000)
                await token.set(access: "fresh")
                return "fresh"
            },
            refreshCoordinator: coordinator
        )

        async let a = interceptor.execute(ProtectedEndpoint())
        async let b = interceptor.execute(ProtectedEndpoint())
        async let c = interceptor.execute(ProtectedEndpoint())
        let (ra, rb, rc) = try await (a, b, c)
        XCTAssertTrue(ra.ok && rb.ok && rc.ok)
        let refreshCount = await refreshCalls.value
        XCTAssertEqual(refreshCount, 1, "Concurrent 401s must share one refresh attempt")
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private actor Flag {
    private(set) var isSet = false
    func raise() { isSet = true }
}

private actor TokenStore {
    private(set) var access: String
    init(access: String) { self.access = access }
    func set(access: String) { self.access = access }
}
