// LuminaVaultClient/LuminaVaultClientTests/AuthHTTPClientTests.swift
// HER-213: round-trip tests for /me and /logout against Shared DTOs.
import XCTest
@testable import LuminaVaultClient

final class AuthHTTPClientTests: XCTestCase {
    var base: BaseHTTPClient!
    var auth: AuthHTTPClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        base = BaseHTTPClient(
            session: session
        )
        auth = AuthHTTPClient(client: base)
    }

    func testGetMeDecodesMeResponseFromSharedDTO() async throws {
        let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/auth/me")
            XCTAssertEqual(request.httpMethod, "GET")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let body = """
            {
              "userId":"\(userId.uuidString)",
              "email":"a@b.co",
              "username":"abby",
              "isVerified":true,
              "privacyNoCNOrigin":false,
              "contextRouting":true
            }
            """.data(using: .utf8)!
            return (response, body)
        }

        let me = try await auth.getMe()
        XCTAssertEqual(me.userId, userId)
        XCTAssertEqual(me.email, "a@b.co")
        XCTAssertEqual(me.username, "abby")
        XCTAssertTrue(me.isVerified)
        XCTAssertFalse(me.privacyNoCNOrigin)
        XCTAssertTrue(me.contextRouting)
    }

    func testLogoutPostsRefreshTokenAndIgnoresEmptyBody() async throws {
        let sent = expectation(description: "request sent")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/auth/logout")
            XCTAssertEqual(request.httpMethod, "POST")
            if let body = request.bodyData() {
                let decoded = try? JSONDecoder().decode(
                    [String: String].self, from: body
                )
                XCTAssertEqual(decoded?["refreshToken"], "rt-abc")
            } else {
                XCTFail("expected refresh-token body")
            }
            sent.fulfill()
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, "{}".data(using: .utf8)!)
        }

        try await auth.logout(refreshToken: "rt-abc")
        await fulfillment(of: [sent], timeout: 1.0)
    }

    func testUpdatePrivacyPutsPatchBodyAndDecodesUpdatedMeResponse() async throws {
        let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000043")!
        let sent = expectation(description: "privacy update sent")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/auth/me/privacy")
            XCTAssertEqual(request.httpMethod, "PUT")
            if let body = request.bodyData() {
                let decoded = try JSONDecoder().decode([String: Bool].self, from: body)
                XCTAssertEqual(decoded["autoSaveLinks"], false)
                XCTAssertEqual(decoded["mnemosyneEnabled"], true)
                XCTAssertNil(decoded["privacyNoCNOrigin"])
                XCTAssertNil(decoded["contextRouting"])
            } else {
                XCTFail("expected privacy update body")
            }
            sent.fulfill()
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let body = """
            {
              "userId":"\(userId.uuidString)",
              "email":"a@b.co",
              "username":"abby",
              "isVerified":true,
              "privacyNoCNOrigin":true,
              "contextRouting":false,
              "autoSaveLinks":false,
              "mnemosyneEnabled":true
            }
            """.data(using: .utf8)!
            return (response, body)
        }

        let me = try await auth.updatePrivacy(
            UpdatePrivacyRequest(
                privacyNoCNOrigin: nil,
                contextRouting: nil,
                autoSaveLinks: false,
                mnemosyneEnabled: true
            )
        )

        await fulfillment(of: [sent], timeout: 1.0)
        XCTAssertEqual(me.userId, userId)
        XCTAssertFalse(me.autoSaveLinks)
        XCTAssertTrue(me.mnemosyneEnabled)
    }
}

private extension URLRequest {
    /// MockURLProtocol strips httpBody when the request becomes a body-stream.
    /// Re-materialise it for assertion.
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
