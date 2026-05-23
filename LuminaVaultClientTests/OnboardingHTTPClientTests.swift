// LuminaVaultClient/LuminaVaultClientTests/OnboardingHTTPClientTests.swift
// HER-100 — wire-format round-trip for GET + PATCH /v1/onboarding.

import XCTest
import LuminaVaultShared
@testable import LuminaVaultClient

final class OnboardingHTTPClientTests: XCTestCase {
    var base: BaseHTTPClient!
    var client: OnboardingHTTPClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        base = BaseHTTPClient(session: session)
        client = OnboardingHTTPClient(client: base)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testGetDecodesOnboardingStateDTO() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/onboarding")
            XCTAssertEqual(request.httpMethod, "GET")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let body = """
            {
              "signupCompleted": true,
              "emailVerifiedCompleted": true,
              "soulConfiguredCompleted": false,
              "firstCaptureCompleted": false,
              "firstKBCompileCompleted": false,
              "firstQueryCompleted": false
            }
            """.data(using: .utf8)!
            return (response, body)
        }

        let state = try await client.get()
        XCTAssertTrue(state.signupCompleted)
        XCTAssertFalse(state.soulConfiguredCompleted)
    }

    func testPatchPostsBodyAndDecodesUpdatedState() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/onboarding")
            XCTAssertEqual(request.httpMethod, "PATCH")
            let body = request.bodyData() ?? Data()
            let decoded = try? JSONDecoder().decode(
                OnboardingPatchRequest.self, from: body
            )
            XCTAssertEqual(decoded?.soulConfiguredCompleted, true)
            XCTAssertNil(decoded?.signupCompleted)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let payload = """
            {
              "signupCompleted": true,
              "emailVerifiedCompleted": true,
              "soulConfiguredCompleted": true,
              "firstCaptureCompleted": false,
              "firstKBCompileCompleted": false,
              "firstQueryCompleted": false
            }
            """.data(using: .utf8)!
            return (response, payload)
        }

        let updated = try await client.patch(
            OnboardingPatchRequest(soulConfiguredCompleted: true)
        )
        XCTAssertTrue(updated.soulConfiguredCompleted)
    }
}

private extension URLRequest {
    /// MockURLProtocol strips `httpBody` when the request becomes a body-
    /// stream. Re-materialise it for assertion.
    func bodyData() -> Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buf, maxLength: 4096)
            if read <= 0 { break }
            data.append(buf, count: read)
        }
        return data
    }
}
