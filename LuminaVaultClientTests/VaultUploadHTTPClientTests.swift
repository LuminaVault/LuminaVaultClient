// LuminaVaultClient/LuminaVaultClientTests/VaultUploadHTTPClientTests.swift
//
// HER-34 — assert HEIC + JPEG content-type passthrough and the
// query-param-encoded vault path.

import XCTest
@testable import LuminaVaultClient
import LuminaVaultShared

final class VaultUploadHTTPClientTests: XCTestCase {
    private var client: VaultUploadHTTPClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let base = BaseHTTPClient(
            baseURL: URL(string: "http://test.local")!,
            session: session,
            tokenProvider: { "test-bearer" },
        )
        client = VaultUploadHTTPClient(client: base)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testUploadAssetSendsHEIC() async throws {
        let captured = CaptureBox()
        MockURLProtocol.handler = { req in
            captured.method = req.httpMethod
            captured.url = req.url
            captured.contentType = req.value(forHTTPHeaderField: "Content-Type")
            captured.authorization = req.value(forHTTPHeaderField: "Authorization")
            let body = #"{"path":"raw/captures/x.heic","size":12,"content_type":"image/heic","sha256":"deadbeef"}"#
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8),
            )
        }

        let resp = try await client.uploadAsset(
            data: Data(repeating: 0xAA, count: 12),
            contentType: "image/heic",
            relativePath: "raw/captures/x.heic",
        )

        XCTAssertEqual(resp.path, "raw/captures/x.heic")
        XCTAssertEqual(resp.contentType, "image/heic")
        XCTAssertEqual(captured.method, "POST")
        XCTAssertEqual(captured.url?.path, "/v1/vault/files")
        XCTAssertEqual(captured.url?.query, "path=raw/captures/x.heic")
        XCTAssertEqual(captured.contentType, "image/heic")
        XCTAssertEqual(captured.authorization, "Bearer test-bearer")
    }

    func testUploadAssetSendsJPEG() async throws {
        let captured = CaptureBox()
        MockURLProtocol.handler = { req in
            captured.contentType = req.value(forHTTPHeaderField: "Content-Type")
            captured.url = req.url
            let body = #"{"path":"raw/captures/y.jpg","size":4,"content_type":"image/jpeg","sha256":"cafe"}"#
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8),
            )
        }

        let resp = try await client.uploadAsset(
            data: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            contentType: "image/jpeg",
            relativePath: "raw/captures/y.jpg",
        )
        XCTAssertEqual(resp.path, "raw/captures/y.jpg")
        XCTAssertEqual(captured.contentType, "image/jpeg")
        XCTAssertEqual(captured.url?.query, "path=raw/captures/y.jpg")
    }
}

private final class CaptureBox: @unchecked Sendable {
    var method: String?
    var url: URL?
    var contentType: String?
    var authorization: String?
}
