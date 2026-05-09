// LuminaVaultClient/LuminaVaultClientTests/BaseHTTPClientTests.swift
import XCTest
@testable import LuminaVaultClient

struct EmptyResponse: Decodable {}

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
}
