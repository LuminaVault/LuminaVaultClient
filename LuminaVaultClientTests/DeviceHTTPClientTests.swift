// LuminaVaultClient/LuminaVaultClientTests/DeviceHTTPClientTests.swift
// HER-214 — wire-format round-trip for POST/DELETE /v1/devices.

import XCTest
import LuminaVaultShared
@testable import LuminaVaultClient

final class DeviceHTTPClientTests: XCTestCase {
    var base: BaseHTTPClient!
    var client: DeviceHTTPClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        base = BaseHTTPClient(session: session)
        client = DeviceHTTPClient(client: base)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testRegisterPostsTokenAndPlatformAndDecodesResponse() async throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000002a1")!
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/devices")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = request.bodyData() ?? Data()
            let decoded = try? JSONDecoder().decode(
                DeviceRegistrationRequest.self, from: body
            )
            XCTAssertEqual(decoded?.token, "deadbeef")
            XCTAssertEqual(decoded?.platform, .ios)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let payload = """
            {"id":"\(id.uuidString)","token":"deadbeef","platform":"ios"}
            """.data(using: .utf8)!
            return (response, payload)
        }

        let result = try await client.register(
            DeviceRegistrationRequest(token: "deadbeef", platform: .ios)
        )
        XCTAssertEqual(result.id, id)
        XCTAssertEqual(result.token, "deadbeef")
        XCTAssertEqual(result.platform, "ios")
    }

    func testUnregisterCallsDeleteWithEscapedTokenInPath() async throws {
        let sent = expectation(description: "delete sent")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/devices/abc123")
            XCTAssertEqual(request.httpMethod, "DELETE")
            sent.fulfill()
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 204,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        try await client.unregister(token: "abc123")
        await fulfillment(of: [sent], timeout: 2)
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
